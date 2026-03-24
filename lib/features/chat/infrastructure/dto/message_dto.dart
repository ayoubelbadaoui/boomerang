import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';

class MessageDto {
  const MessageDto({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String senderId;
  final String text;
  final String type;
  final Timestamp createdAt;
  final String status;

  factory MessageDto.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MessageDto(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      status: data['status'] as String? ?? 'sent',
    );
  }

  MessageEntity toEntity() {
    return MessageEntity(
      id: id,
      senderId: senderId,
      text: text,
      type: type == 'image' ? MessageType.image : MessageType.text,
      createdAt: createdAt.toDate(),
      status: _parseStatus(status),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'type': type,
      'createdAt': createdAt,
      'status': status,
    };
  }

  static MessageStatus _parseStatus(String value) {
    switch (value) {
      case 'delivered':
        return MessageStatus.delivered;
      case 'seen':
        return MessageStatus.seen;
      default:
        return MessageStatus.sent;
    }
  }

  static String statusToString(MessageStatus status) {
    switch (status) {
      case MessageStatus.delivered:
        return 'delivered';
      case MessageStatus.seen:
        return 'seen';
      case MessageStatus.sent:
        return 'sent';
    }
  }
}
