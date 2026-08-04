import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot intent raised by push/local notification taps.
///
/// [HomeShell] (and other ready surfaces) consume this after auth/profile
/// gates settle so cold-start opens do not race splash redirects.
enum NotificationNavKind { chat, boomerang, activity }

class NotificationNavIntent {
  const NotificationNavIntent({
    required this.kind,
    this.id,
  });

  final NotificationNavKind kind;
  final String? id;
}

final pendingNotificationNavProvider =
    StateProvider<NotificationNavIntent?>((ref) => null);
