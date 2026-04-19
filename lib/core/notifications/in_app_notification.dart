import 'package:flutter_riverpod/flutter_riverpod.dart';

class InAppNotification {
  const InAppNotification({
    required this.title,
    required this.body,
    this.avatarUrl,
    this.conversationId,
  });

  final String title;
  final String body;
  final String? avatarUrl;
  final String? conversationId;
}

final inAppNotificationProvider = StateProvider<InAppNotification?>((ref) => null);
