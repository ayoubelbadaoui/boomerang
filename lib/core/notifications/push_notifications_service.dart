import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Boots push notifications:
/// - Requests permission (required on iOS)
/// - Ensures foreground presentation on iOS
/// - Saves the FCM token under users/{uid}/deviceTokens/{token}
/// - Keeps the token in sync on refresh
/// - Hooks basic onMessage handler
/// Removes this device's FCM token from the given user's document so the device
/// stops receiving push notifications for that user. Call before logout.
Future<void> removeCurrentDeviceTokenForUser(
  FirebaseFirestore fs,
  String uid,
) async {
  if (uid.isEmpty) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    final tokenRef = fs
        .collection('users')
        .doc(uid)
        .collection('deviceTokens')
        .doc(token);
    await tokenRef.delete();
    developer.log(
      '[notification push] ✅ FCM token removed for user: $uid (logout)',
    );
  } catch (e) {
    developer.log(
      '[notification push] ⚠️ Could not remove FCM token: $e',
      error: e,
    );
  }
}

final pushNotificationsProvider = Provider<void>((ref) {
  _PushNotificationsBootstrap(ref).initialize();
});

class _PushNotificationsBootstrap {
  _PushNotificationsBootstrap(this.ref);
  final Ref ref;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

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
      await _initLocalNotifications();
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
        _initLocalNotifications().then((_) {
          _saveCurrentTokenForUser(currentUser.uid);
        });
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
      await _showLocalNotification(message);
    });

    // Background tap → navigate to conversation
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // App was terminated and opened via notification
    _messaging.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message);
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final conversationId = message.data['conversationId'] as String?;
    if (type == 'chat_message' && conversationId != null) {
      router.push('/chat/$conversationId');
      return;
    }
    const socialTypes = {'like', 'comment', 'reply', 'follow', 'follow_back', 'follow_request'};
    if (type != null && socialTypes.contains(type)) {
      router.go('/home');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Android channel setup
    const androidChannel = AndroidNotificationChannel(
      'boomerang_push',
      'Boomerang Notifications',
      description: 'Push notifications for Boomerang',
      importance: Importance.max,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
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
    try {
      final token = await _messaging.getToken();
      developer.log('[notification push] 📱 FCM Token: ${token ?? "NULL"}');
      if (token == null || token.isEmpty) {
        developer.log('[notification push] ⚠️ FCM token is null or empty');
        return;
      }
      await _saveToken(uid, token);
      developer.log('[notification push] ✅ FCM token saved for user: $uid');
    } catch (e) {
      // On iOS the APNS token may not be available yet (e.g. simulator, or
      // before the OS has delivered it). Swallow the error so it doesn't
      // propagate as an unhandled exception that janks the UI thread.
      developer.log(
        '[notification push] ⚠️ Could not get FCM token (APNS may not be ready): $e',
      );
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
      developer.log(
        '[notification push] Failed to save FCM token: $e',
        error: e,
      );
    }
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('chat:')) {
      final conversationId = payload.substring(5);
      router.push('/chat/$conversationId');
      return;
    }
    if (payload.startsWith('social:')) {
      router.go('/home');
    }
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (e) {
      developer.log('[notification push] Failed to download avatar: $e');
    }
    return null;
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'Boomerang';
    final body = message.notification?.body ?? 'New notification';

    final avatarUrl = message.data['avatarUrl'] as String?;
    ByteArrayAndroidBitmap? largeIcon;
    if (Platform.isAndroid &&
        avatarUrl != null &&
        avatarUrl.isNotEmpty) {
      final bytes = await _downloadImage(avatarUrl);
      if (bytes != null) largeIcon = ByteArrayAndroidBitmap(bytes);
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'boomerang_push',
        'Boomerang Notifications',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: largeIcon,
        playSound: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    final type = message.data['type'] as String? ?? '';
    String payload = '';
    if (type == 'chat_message') {
      payload = 'chat:${message.data['conversationId'] ?? ''}';
    } else if (const {'like', 'comment', 'reply', 'follow', 'follow_back', 'follow_request'}.contains(type)) {
      payload = 'social:${message.data['resourceId'] ?? ''}';
    }

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
