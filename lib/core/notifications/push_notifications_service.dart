import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:boomerang/core/navigation/notification_navigation.dart';
import 'package:boomerang/core/notifications/in_app_notification.dart';
import 'package:boomerang/core/utils/perf_log.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Boots push notifications:
/// - Requests permission (required on iOS / Android 13+)
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

  static const _androidChannel = AndroidNotificationChannel(
    'boomerang_push',
    'Boomerang Notifications',
    description: 'Push notifications for Boomerang',
    importance: Importance.max,
  );

  static const _contentTypes = {
    'like',
    'comment',
    'reply',
  };
  static const _activityTypes = {
    'follow',
    'follow_back',
    'follow_request',
  };

  bool _localReady = false;
  bool _routingReady = false;
  NotificationNavIntent? _pendingIntent;

  void initialize() {
    // Create the Android channel once at cold start (before auth) so early
    // FCM deliveries have a defined high-importance channel.
    // ignore: discarded_futures
    _ensureLocalNotifications();

    // React to auth changes and keep token saved when signed in
    ref.listen(authStateProvider, (prev, next) async {
      final user = next.asData?.value;
      if (user == null) {
        developer.log(
          '[notification push] ⚠️ No user signed in - FCM token will not be saved',
        );
        _routingReady = false;
        return;
      }
      developer.log(
        '[notification push] 👤 User signed in: ${user.uid} - Configuring notifications...',
      );
      await PerfLog.track(
        'push.permissions',
        _configurePermissionsAndPresentation,
      );
      await PerfLog.track('push.localInit', _ensureLocalNotifications);
      await PerfLog.track(
        'push.saveToken',
        () => _saveCurrentTokenForUser(user.uid),
      );
    });

    // Also try to get token immediately if user is already signed in
    final auth = ref.read(firebaseAuthProvider);
    final currentUser = auth.currentUser;
    if (currentUser != null) {
      developer.log(
        '[notification push] 👤 User already signed in: ${currentUser.uid} - Getting token...',
      );
      _configurePermissionsAndPresentation().then((_) {
        _ensureLocalNotifications().then((_) {
          _saveCurrentTokenForUser(currentUser.uid);
        });
      });
    }

    // Wait until profile gates settle before applying notification deep links.
    ref.listen(userHasNicknameProvider, (prev, next) {
      _maybeEnableRouting();
    });
    ref.listen(userProfileCompleteProvider, (prev, next) {
      _maybeEnableRouting();
    });
    _maybeEnableRouting();

    // Token refresh handling
    _messaging.onTokenRefresh.listen((token) async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) return;
      await _saveToken(user.uid, token);
    });

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      developer.log(
        '[notification push] FCM foreground message: ${message.messageId} '
        'title=${message.notification?.title} body=${message.notification?.body}',
      );

      final type = message.data['type'] as String?;
      final conversationId = message.data['conversationId'] as String?;

      if (type == 'chat_message' && conversationId != null) {
        final activeConvId = ref.read(activeConversationProvider);
        if (activeConvId == conversationId) {
          developer.log(
            '[notification push] Suppressed — chat $conversationId is active',
          );
          return;
        }

        // Show Instagram-style in-app banner instead of a system notification
        final title = message.notification?.title
            ?? message.data['senderName'] as String?
            ?? 'Boomerang';
        final body = message.notification?.body
            ?? message.data['body'] as String?
            ?? 'New message';
        final avatarUrl = message.data['avatarUrl'] as String?;

        ref.read(inAppNotificationProvider.notifier).state = InAppNotification(
          title: title,
          body: body,
          avatarUrl: avatarUrl,
          conversationId: conversationId,
        );
        return;
      }

      await _showLocalNotification(message);
    });

    // Background tap → navigate
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // App was terminated and opened via notification — defer until routing ready.
    _messaging.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message);
    });
  }

  void _maybeEnableRouting() {
    final auth = ref.read(authStateProvider);
    final hasNickname = ref.read(userHasNicknameProvider);
    final profileComplete = ref.read(userProfileCompleteProvider);
    final user = auth.asData?.value;
    final ready =
        user != null &&
        hasNickname.asData?.value == true &&
        profileComplete.asData?.value == true;
    if (!ready) return;
    if (_routingReady) return;
    _routingReady = true;
    final pending = _pendingIntent;
    _pendingIntent = null;
    if (pending != null) {
      _dispatchIntent(pending);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final intent = _intentFromRemote(message);
    if (intent == null) return;
    _queueOrDispatch(intent);
  }

  NotificationNavIntent? _intentFromRemote(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final conversationId = message.data['conversationId'] as String?;
    if (type == 'chat_message' &&
        conversationId != null &&
        conversationId.isNotEmpty) {
      return NotificationNavIntent(
        kind: NotificationNavKind.chat,
        id: conversationId,
      );
    }
    final resourceId = message.data['resourceId'] as String?;
    if (type != null &&
        _contentTypes.contains(type) &&
        resourceId != null &&
        resourceId.isNotEmpty) {
      return NotificationNavIntent(
        kind: NotificationNavKind.boomerang,
        id: resourceId,
      );
    }
    if (type != null && _activityTypes.contains(type)) {
      return const NotificationNavIntent(kind: NotificationNavKind.activity);
    }
    return null;
  }

  void _queueOrDispatch(NotificationNavIntent intent) {
    if (!_routingReady) {
      _pendingIntent = intent;
      return;
    }
    _dispatchIntent(intent);
  }

  void _dispatchIntent(NotificationNavIntent intent) {
    // Prefer a pending intent for HomeShell-owned surfaces (activity list),
    // and go_router for deep routes that already exist.
    switch (intent.kind) {
      case NotificationNavKind.chat:
        final id = intent.id;
        if (id == null || id.isEmpty) return;
        ref.read(routerProvider).go('/home');
        ref.read(routerProvider).push('/chat/$id');
        return;
      case NotificationNavKind.boomerang:
        final id = intent.id;
        if (id == null || id.isEmpty) {
          ref.read(pendingNotificationNavProvider.notifier).state =
              const NotificationNavIntent(kind: NotificationNavKind.activity);
          ref.read(routerProvider).go('/home');
          return;
        }
        ref.read(routerProvider).go('/home');
        ref.read(routerProvider).push('/boomerang/$id');
        return;
      case NotificationNavKind.activity:
        ref.read(pendingNotificationNavProvider.notifier).state = intent;
        ref.read(routerProvider).go('/home');
        return;
    }
  }

  Future<void> _ensureLocalNotifications() async {
    if (_localReady) return;
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_boomerang');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    // Local notification cold-start (foreground → process death → tap).
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final response = launch!.notificationResponse;
      if (response != null) _onLocalNotificationTap(response);
    }

    _localReady = true;
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
      // Disable system-level foreground banners so we control display via
      // flutter_local_notifications (allows per-conversation suppression).
      // Badge is false because in-app UI handles unread state; the native
      // AppDelegate clears the OS badge on open/resume.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
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
      if (conversationId.isEmpty) return;
      _queueOrDispatch(
        NotificationNavIntent(
          kind: NotificationNavKind.chat,
          id: conversationId,
        ),
      );
      return;
    }
    if (payload.startsWith('boomerang:')) {
      final id = payload.substring(10);
      _queueOrDispatch(
        NotificationNavIntent(
          kind: NotificationNavKind.boomerang,
          id: id.isEmpty ? null : id,
        ),
      );
      return;
    }
    if (payload.startsWith('social:')) {
      _queueOrDispatch(
        const NotificationNavIntent(kind: NotificationNavKind.activity),
      );
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
    await _ensureLocalNotifications();

    final title = message.notification?.title
        ?? message.data['senderName'] as String?
        ?? 'Boomerang';
    final body = message.notification?.body
        ?? message.data['body'] as String?
        ?? 'New notification';

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
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@drawable/ic_stat_boomerang',
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
    } else if (_contentTypes.contains(type)) {
      payload = 'boomerang:${message.data['resourceId'] ?? ''}';
    } else if (_activityTypes.contains(type)) {
      payload = 'social:${message.data['resourceId'] ?? ''}';
    }

    // Millisecond id (31-bit) so bursts in the same second don't replace each
    // other on Android's NotificationManager.
    await _local.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
