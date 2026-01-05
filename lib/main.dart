import 'dart:io';

import 'package:boomerang/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

// Top-level background handler for FCM messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized when the process is woken up
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  late final Future<_BootstrapState> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<_BootstrapState> _initialize() async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) return _BootstrapState.offline;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return _BootstrapState.ready;
    } catch (_) {
      return _BootstrapState.error;
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
          return const _OfflineApp(
            title: 'No internet connection',
            message:
                'Please connect to the internet to finish starting Boomerang.',
          );
        }
        if (state == _BootstrapState.error) {
          return const _OfflineApp(
            title: 'Couldn\u2019t start',
            message: 'There was a problem starting the app. Please try again.',
          );
        }
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _OfflineApp extends StatelessWidget {
  const _OfflineApp({required this.title, required this.message});

  final String title;
  final String message;

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
  try {
    final result = await InternetAddress.lookup(
      'clients3.google.com',
    ).timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
