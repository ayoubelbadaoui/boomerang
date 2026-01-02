import 'dart:developer' as developer;
import 'dart:io';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Boots push notifications:
/// - Requests permission (required on iOS)
/// - Ensures foreground presentation on iOS
/// - Saves the FCM token under users/{uid}/deviceTokens/{token}
/// - Keeps the token in sync on refresh
/// - Hooks basic onMessage handler
final pushNotificationsProvider = Provider<void>((ref) {
  _PushNotificationsBootstrap(ref).initialize();
});

class _PushNotificationsBootstrap {
  _PushNotificationsBootstrap(this.ref);
  final Ref ref;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  void initialize() {
    // React to auth changes and keep token saved when signed in
    ref.listen(authStateProvider, (prev, next) async {
      final user = next.asData?.value;
      if (user == null) {
        developer.log(
          '[notification push] ⚠️ No user signed in - FCM token will not be saved',
        );
        return;
      }
      developer.log(
        '[notification push] 👤 User signed in: ${user.uid} - Configuring notifications...',
      );
      await _configurePermissionsAndPresentation();
      await _saveCurrentTokenForUser(user.uid);
    });

    // Also try to get token immediately if user is already signed in
    final auth = ref.read(firebaseAuthProvider);
    final currentUser = auth.currentUser;
    if (currentUser != null) {
      developer.log(
        '[notification push] 👤 User already signed in: ${currentUser.uid} - Getting token...',
      );
      _configurePermissionsAndPresentation().then((_) {
        _saveCurrentTokenForUser(currentUser.uid);
      });
    }

    // Token refresh handling
    _messaging.onTokenRefresh.listen((token) async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) return;
      await _saveToken(user.uid, token);
    });

    // Foreground message handler (basic no-UI handler)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      developer.log(
        '[notification push] FCM foreground message: ${message.messageId} '
        'title=${message.notification?.title} body=${message.notification?.body}',
      );
      // For full foreground notifications, integrate a local notifications plugin.
    });
  }

  Future<void> _configurePermissionsAndPresentation() async {
    // iOS/Apple platforms: request permission and allow heads-up in foreground
    if (Platform.isIOS || Platform.isMacOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      developer.log(
        '[notification push] 📱 APNs permission status: ${settings.authorizationStatus}',
      );
      developer.log('[notification push]    - Alert: ${settings.alert}');
      developer.log('[notification push]    - Badge: ${settings.badge}');
      developer.log('[notification push]    - Sound: ${settings.sound}');
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Android: Request notification permission for Android 13+
    if (Platform.isAndroid) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      developer.log(
        '[notification push] 📱 Android notification permission: ${settings.authorizationStatus}',
      );
    }
  }

  Future<void> _saveCurrentTokenForUser(String uid) async {
    final token = await _messaging.getToken();
    developer.log('[notification push] 📱 FCM Token: ${token ?? "NULL"}');
    if (token == null || token.isEmpty) {
      developer.log('[notification push] ⚠️ FCM token is null or empty');
      return;
    }
    await _saveToken(uid, token);
    developer.log('[notification push] ✅ FCM token saved for user: $uid');
  }

  Future<void> _saveToken(String uid, String token) async {
    final fs = ref.read(firestoreProvider);
    final tokenRef = fs
        .collection('users')
        .doc(uid)
        .collection('deviceTokens')
        .doc(token);
    final payload = <String, dynamic>{
      'platform':
          Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
              ? 'android'
              : Platform.isMacOS
              ? 'macos'
              : Platform.isWindows
              ? 'windows'
              : Platform.isLinux
              ? 'linux'
              : 'unknown',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await tokenRef.set(payload, SetOptions(merge: true));
    } catch (e) {
      developer.log(
        '[notification push] Failed to save FCM token: $e',
        error: e,
      );
    }
  }
}
