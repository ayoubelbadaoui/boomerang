import 'dart:io';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
        return;
      }
      await _configurePermissionsAndPresentation();
      await _saveCurrentTokenForUser(user.uid);
    });

    // Token refresh handling
    _messaging.onTokenRefresh.listen((token) async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) return;
      await _saveToken(user.uid, token);
    });

    // Foreground message handler (basic no-UI handler)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        debugPrint(
          'FCM foreground message: ${message.messageId} '
          'title=${message.notification?.title} body=${message.notification?.body}',
        );
      }
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
      if (kDebugMode) {
        debugPrint(
          '📱 APNs permission status: ${settings.authorizationStatus}',
        );
        debugPrint('   - Alert: ${settings.alert}');
        debugPrint('   - Badge: ${settings.badge}');
        debugPrint('   - Sound: ${settings.sound}');
      }
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _saveCurrentTokenForUser(String uid) async {
    final token = await _messaging.getToken();
    if (kDebugMode) {
      debugPrint('📱 FCM Token: ${token ?? "NULL"}');
    }
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ FCM token is null or empty');
      }
      return;
    }
    await _saveToken(uid, token);
    if (kDebugMode) {
      debugPrint('✅ FCM token saved for user: $uid');
    }
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
      if (kDebugMode) {
        debugPrint('Failed to save FCM token: $e');
      }
    }
  }
}
