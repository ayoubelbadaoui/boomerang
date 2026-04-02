enum MessageType { text, image, gif, audio }

enum MessageStatus { sent, delivered, seen }

class MessageEntity {
  const MessageEntity({
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
  final MessageType type;
  final DateTime createdAt;
  final MessageStatus status;
  final bool isUnsent;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderId;
  final MessageType? replyToType;
  final int? audioDurationMs;

  MessageEntity copyWith({
    String? id,
    String? senderId,
    String? text,
    MessageType? type,
    DateTime? createdAt,
    MessageStatus? status,
    bool? isUnsent,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    MessageType? replyToType,
    int? audioDurationMs,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isUnsent: isUnsent ?? this.isUnsent,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToType: replyToType ?? this.replyToType,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
    );
  }

  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isSeen => status == MessageStatus.seen;
  bool get isImage => type == MessageType.image;
  bool get isGif => type == MessageType.gif;
  bool get isAudio => type == MessageType.audio;
  bool get hasReply => replyToMessageId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
