enum MessageType { text, image }

enum MessageStatus { sent, delivered, seen }

class MessageEntity {
  const MessageEntity({
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
  final MessageType type;
  final DateTime createdAt;
  final MessageStatus status;

  MessageEntity copyWith({
    String? id,
    String? senderId,
    String? text,
    MessageType? type,
    DateTime? createdAt,
    MessageStatus? status,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }

  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isSeen => status == MessageStatus.seen;
  bool get isImage => type == MessageType.image;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
