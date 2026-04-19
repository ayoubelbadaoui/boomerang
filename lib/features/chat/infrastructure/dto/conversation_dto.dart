import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';

class ConversationDto {
  const ConversationDto({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.unreadCount,
    required this.createdAt,
    this.pinnedBy = const [],
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final Timestamp lastMessageAt;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final Timestamp createdAt;
  final List<String> pinnedBy;

  factory ConversationDto.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final rawUnread = data['unreadCount'] as Map<String, dynamic>? ?? {};
    return ConversationDto(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: data['lastMessageAt'] as Timestamp? ?? Timestamp.now(),
      lastMessageSenderId: data['lastMessageSenderId'] as String? ?? '',
      unreadCount: rawUnread.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      pinnedBy: List<String>.from(data['pinnedBy'] ?? []),
    );
  }

  ConversationEntity toEntity() {
    return ConversationEntity(
      id: id,
      participants: participants,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt.toDate(),
      lastMessageSenderId: lastMessageSenderId,
      unreadCount: unreadCount,
      createdAt: createdAt.toDate(),
      pinnedBy: pinnedBy,
    );
  }
}
