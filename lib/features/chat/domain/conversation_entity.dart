class ConversationEntity {
  const ConversationEntity({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.unreadCount,
    required this.createdAt,
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final DateTime createdAt;

  int unreadCountFor(String userId) => unreadCount[userId] ?? 0;

  String otherParticipantId(String currentUserId) {
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
