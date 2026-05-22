import 'package:boomerang/features/chat/application/chat_controller.dart';
import 'package:boomerang/features/chat/domain/chat_repo.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChatRepo implements ChatRepo {
  String? lastText;
  MessageType? lastType;
  String? lastSharedPostId;
  String? lastSharedPostImageUrl;
  String? lastSharedPostUserName;
  String? lastSharedPostCaption;

  @override
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
  }) async {
    lastText = text;
    lastType = type;
    lastSharedPostId = sharedPostId;
    lastSharedPostImageUrl = sharedPostImageUrl;
    lastSharedPostUserName = sharedPostUserName;
    lastSharedPostCaption = sharedPostCaption;
    return MessageEntity(
      id: 'm1',
      senderId: senderId,
      text: text,
      type: type,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      sharedPostId: sharedPostId,
      sharedPostImageUrl: sharedPostImageUrl,
      sharedPostUserName: sharedPostUserName,
      sharedPostCaption: sharedPostCaption,
    );
  }

  @override
  Stream<List<ConversationEntity>> streamConversations(String userId) =>
      const Stream.empty();

  @override
  Stream<List<MessageEntity>> streamMessages(String conversationId, {int limit = 20}) =>
      Stream.value(const []);

  @override
  Future<List<MessageEntity>> loadMoreMessages(
    String conversationId, {
    required DateTime before,
    int limit = 20,
  }) async => const [];

  @override
  Future<void> markMessagesAsSeen(String conversationId, String userId) async {}

  @override
  Future<String> getOrCreateConversation(List<String> participantIds) async => 'conv';

  @override
  Future<String> uploadChatImage(String conversationId, String localPath) async =>
      'https://image';

  @override
  Future<String> uploadChatAudio(String conversationId, String localPath) async =>
      'https://audio';

  @override
  Future<void> unsendMessage({
    required String conversationId,
    required String messageId,
  }) async {}

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {}

  @override
  Future<void> pinConversation({
    required String conversationId,
    required String userId,
  }) async {}

  @override
  Future<void> unpinConversation({
    required String conversationId,
    required String userId,
  }) async {}

  @override
  Future<void> deleteConversation({
    required String conversationId,
    required String userId,
  }) async {}

  @override
  Future<void> deleteConversations({
    required List<String> conversationIds,
    required String userId,
  }) async {}
}

void main() {
  test('sendSharedPostMessage uses readable placeholder text', () async {
    final repo = _FakeChatRepo();
    final controller = ChatController(
      repo: repo,
      conversationId: 'c1',
      currentUserId: 'u1',
    );
    addTearDown(controller.dispose);

    await controller.sendSharedPostMessage(
      boomerangId: 'raw_boomerang_doc_id_123',
      imageUrl: 'https://image',
      userName: 'Alice',
      caption: 'caption',
    );

    expect(repo.lastType, MessageType.sharedPost);
    expect(repo.lastText, '📫 Shared a post');
    expect(repo.lastText, isNot('raw_boomerang_doc_id_123'));
    expect(repo.lastSharedPostId, 'raw_boomerang_doc_id_123');
    expect(repo.lastSharedPostImageUrl, 'https://image');
    expect(repo.lastSharedPostUserName, 'Alice');
    expect(repo.lastSharedPostCaption, 'caption');
  });
}
