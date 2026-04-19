import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';

abstract class ChatRepo {
  Stream<List<ConversationEntity>> streamConversations(String userId);

  Stream<List<MessageEntity>> streamMessages(
    String conversationId, {
    int limit = 20,
  });

  Future<MessageEntity> sendMessage(
    String conversationId, {
    required String senderId,
    required String text,
    required MessageType type,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    MessageType? replyToType,
    int? audioDurationMs,
    String? sharedPostId,
    String? sharedPostImageUrl,
    String? sharedPostUserName,
    String? sharedPostCaption,
  });

  Future<List<MessageEntity>> loadMoreMessages(
    String conversationId, {
    required DateTime before,
    int limit = 20,
  });

  Future<void> markMessagesAsSeen(String conversationId, String userId);

  Future<String> getOrCreateConversation(List<String> participantIds);

  Future<String> uploadChatImage(String conversationId, String localPath);

  Future<String> uploadChatAudio(String conversationId, String localPath);

  Future<void> unsendMessage({
    required String conversationId,
    required String messageId,
  });

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  });

  Future<void> pinConversation({
    required String conversationId,
    required String userId,
  });

  Future<void> unpinConversation({
    required String conversationId,
    required String userId,
  });

  Future<void> deleteConversation({
    required String conversationId,
    required String userId,
  });

  Future<void> deleteConversations({
    required List<String> conversationIds,
    required String userId,
  });
}
