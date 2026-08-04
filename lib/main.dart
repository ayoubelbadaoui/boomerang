import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/core/audio/app_audio_session.dart';
import 'package:boomerang/core/assets/shared_assets.dart';
import 'package:boomerang/core/utils/perf_log.dart';
import 'package:boomerang/firebase_options.dart';
import 'package:boomerang/infrastructure/auth/install_session_guard.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

// Top-level background handler for FCM messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized when the process is woken up
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Match iOS-style edge-to-edge chrome: transparent bars; fullscreen routes
  // still use ImmersiveSystemUi to hide overlays entirely.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Poster disk cache (CachedNetworkImage) handles scroll-back; keep in-memory
  // budget modest so video decoders still have headroom on low-RAM devices.
  // Android MediaCodec heaps compete harder — keep a tighter Flutter image cache.
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      (Platform.isAndroid ? 64 : 96) * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = Platform.isAndroid ? 160 : 200;

  // Let background music (Spotify, Apple Music, etc.) keep playing.
  // Videos in this app are muted; voice notes switch to a playback session on demand.
  await configureAmbientAudioSession();

  // Register the background message handler before initializing the app
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: _BootstrapApp()));
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

enum _BootstrapState { ready, offline, error }

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<_BootstrapState> _initialization;
  String? _lastErrorMessage;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    setState(() {
      _lastErrorMessage = null;
      _initialization = _initialize();
    });
  }

  Future<_BootstrapState> _initialize() async {
    PerfLog.event('bootstrap START');
    final hasInternet = await PerfLog.track(
      'bootstrap.connectivityCheck',
      _hasInternetConnection,
    );
    try {
      await PerfLog.track(
        'bootstrap.firebaseInit',
        () => Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ),
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        // Cap persistence so Android native heap does not grow unboundedly.
        cacheSizeBytes: 100 * 1024 * 1024,
      );
      await PerfLog.track(
        'bootstrap.installSessionGuard',
        () => InstallSessionGuard().enforce(),
      );
      PerfLog.event('bootstrap READY');
      return _BootstrapState.ready;
    } catch (e, st) {
      debugPrint('Firebase initialization failed: $e\n$st');
      if (mounted) {
        setState(() {
          _lastErrorMessage = e.toString();
        });
      }
      // If we can reach the network but Firebase fails, surface an error;
      // otherwise treat it as offline so the user can retry.
      return hasInternet ? _BootstrapState.error : _BootstrapState.offline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapState>(
      future: _initialization,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == _BootstrapState.ready) {
          return const BoomerangApp();
        }
        if (state == _BootstrapState.offline) {
          return _OfflineApp(
            title: 'No internet connection',
            message:
                'Please connect to the internet to finish starting Boomerang.',
            onRetry: _startInitialization,
          );
        }
        if (state == _BootstrapState.error) {
          return _OfflineApp(
            title: 'Couldn\u2019t start',
            message: 'There was a problem starting the app. Please try again.',
            details: _lastErrorMessage,
            onRetry: _startInitialization,
          );
        }
        return const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Image(
                image: AssetImage(Assets.logoLight),
                width: 248,
                height: 248,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OfflineApp extends StatelessWidget {
  const _OfflineApp({
    required this.title,
    required this.message,
    this.details,
    this.onRetry,
  });

  final String title;
  final String message;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boomerang',
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 64, color: Colors.black54),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (details != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      details!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _hasInternetConnection() async {
  const hosts = [
    // Multiple hosts to reduce false negatives on networks that block a single domain.
    'example.com',
    'cloudflare.com',
    'google.com',
  ];
  for (final host in hosts) {
    try {
      final result = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 3));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {
      // try next host
    }
  }
  return false;
}
