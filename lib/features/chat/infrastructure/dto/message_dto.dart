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
    this.isUnsent = false,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderId,
    this.replyToType,
    this.audioDurationMs,
  });

  final String id;
  final String senderId;
  final String text;
  final String type;
  final Timestamp createdAt;
  final String status;
  final bool isUnsent;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderId;
  final String? replyToType;
  final int? audioDurationMs;

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
      isUnsent: data['isUnsent'] as bool? ?? false,
      replyToMessageId: data['replyToMessageId'] as String?,
      replyToText: data['replyToText'] as String?,
      replyToSenderId: data['replyToSenderId'] as String?,
      replyToType: data['replyToType'] as String?,
      audioDurationMs: (data['audioDurationMs'] as num?)?.toInt(),
    );
  }

  MessageEntity toEntity() {
    return MessageEntity(
      id: id,
      senderId: senderId,
      text: text,
      type: _parseType(type),
      createdAt: createdAt.toDate(),
      status: _parseStatus(status),
      isUnsent: isUnsent,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      replyToType: replyToType != null ? _parseType(replyToType!) : null,
      audioDurationMs: audioDurationMs,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'type': type,
      'createdAt': createdAt,
      'status': status,
      'isUnsent': isUnsent,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (replyToType != null) 'replyToType': replyToType,
      if (audioDurationMs != null) 'audioDurationMs': audioDurationMs,
    };
  }

  static MessageType _parseType(String value) {
    switch (value) {
      case 'image':
        return MessageType.image;
      case 'gif':
        return MessageType.gif;
      case 'audio':
        return MessageType.audio;
      default:
        return MessageType.text;
    }
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

  static String typeToString(MessageType type) {
    switch (type) {
      case MessageType.image:
        return 'image';
      case MessageType.gif:
        return 'gif';
      case MessageType.audio:
        return 'audio';
      case MessageType.text:
        return 'text';
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
