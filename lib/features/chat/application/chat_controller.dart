import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/features/chat/domain/chat_repo.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isSending = false,
    this.error,
    this.replyingTo,
  });

  final List<MessageEntity> messages;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final String? error;
  final MessageEntity? replyingTo;

  ChatState copyWith({
    List<MessageEntity>? messages,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSending,
    String? error,
    MessageEntity? replyingTo,
    bool clearReply = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      isSending: isSending ?? this.isSending,
      error: error,
      replyingTo: clearReply ? null : (replyingTo ?? this.replyingTo),
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required ChatRepo repo,
    required this.conversationId,
    required this.currentUserId,
  })  : _repo = repo,
        super(const ChatState()) {
    _init();
  }

  final ChatRepo _repo;
  final String conversationId;
  final String currentUserId;
  StreamSubscription<List<MessageEntity>>? _subscription;
  bool _disposed = false;

  static const _pageSize = 20;

  bool _isViewing = false;

  void setViewing(bool viewing) {
    _isViewing = viewing;
    if (viewing) markAsSeen();
  }

  void _init() {
    _subscription = _repo
        .streamMessages(conversationId, limit: _pageSize)
        .listen(
      (streamedMessages) {
        if (_disposed) return;
        final paginatedOlder = state.messages
            .where((m) => !streamedMessages.any((sm) => sm.id == m.id))
            .toList();
        state = state.copyWith(
          messages: [...streamedMessages, ...paginatedOlder],
        );

        if (_isViewing) {
          final hasUnseenFromOthers = streamedMessages.any(
            (m) =>
                m.senderId != currentUserId &&
                m.status != MessageStatus.seen,
          );
          if (hasUnseenFromOthers) {
            _repo.markMessagesAsSeen(conversationId, currentUserId);
          }
        }
      },
      onError: (Object e) {
        if (_disposed) return;
        state = state.copyWith(error: e.toString());
      },
    );
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final oldest = state.messages.last;
      final older = await _repo.loadMoreMessages(
        conversationId,
        before: oldest.createdAt,
        limit: _pageSize,
      );
      if (_disposed) return;

      final existingIds = state.messages.map((m) => m.id).toSet();
      final fresh =
          older.where((m) => !existingIds.contains(m.id)).toList();

      state = state.copyWith(
        messages: [...state.messages, ...fresh],
        isLoadingMore: false,
        hasMore: older.length >= _pageSize,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  // ── Reply ──────────────────────────────────────────────────────────────

  void setReplyTo(MessageEntity message) {
    state = state.copyWith(replyingTo: message);
  }

  void clearReply() {
    state = state.copyWith(clearReply: true);
  }

  // ── Send messages ─────────────────────────────────────────────────────

  String? _replyPreviewText(MessageEntity? reply) {
    if (reply == null) return null;
    if (reply.isImage) return '📷 Photo';
    if (reply.isGif) return 'GIF';
    if (reply.isAudio) return '🎤 Voice message';
    if (reply.isSharedPost) return '📫 Shared a post';
    return reply.text;
  }

  Future<void> sendMessage(
    String text, {
    MessageType type = MessageType.text,
  }) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(isSending: true, error: null);
    try {
      final reply = state.replyingTo;
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: text.trim(),
        type: type,
        replyToMessageId: reply?.id,
        replyToText: _replyPreviewText(reply),
        replyToSenderId: reply?.senderId,
        replyToType: reply?.type,
      );
      if (_disposed) return;
      state = state.copyWith(isSending: false, clearReply: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendImageMessage(String localPath) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      final reply = state.replyingTo;
      final url = await _repo.uploadChatImage(conversationId, localPath);
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: url,
        type: MessageType.image,
        replyToMessageId: reply?.id,
        replyToText: _replyPreviewText(reply),
        replyToSenderId: reply?.senderId,
        replyToType: reply?.type,
      );
      if (_disposed) return;
      state = state.copyWith(isSending: false, clearReply: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendGifMessage(String gifUrl) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      final reply = state.replyingTo;
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: gifUrl,
        type: MessageType.gif,
        replyToMessageId: reply?.id,
        replyToText: _replyPreviewText(reply),
        replyToSenderId: reply?.senderId,
        replyToType: reply?.type,
      );
      if (_disposed) return;
      state = state.copyWith(isSending: false, clearReply: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendSharedPostMessage({
    required String boomerangId,
    required String imageUrl,
    required String userName,
    String? caption,
  }) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      final reply = state.replyingTo;
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: boomerangId,
        type: MessageType.sharedPost,
        replyToMessageId: reply?.id,
        replyToText: _replyPreviewText(reply),
        replyToSenderId: reply?.senderId,
        replyToType: reply?.type,
        sharedPostId: boomerangId,
        sharedPostImageUrl: imageUrl,
        sharedPostUserName: userName,
        sharedPostCaption: caption,
      );
      if (_disposed) return;
      state = state.copyWith(isSending: false, clearReply: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendAudioMessage(String localPath, int durationMs) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      final reply = state.replyingTo;
      final url = await _repo.uploadChatAudio(conversationId, localPath);
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: url,
        type: MessageType.audio,
        audioDurationMs: durationMs,
        replyToMessageId: reply?.id,
        replyToText: _replyPreviewText(reply),
        replyToSenderId: reply?.senderId,
        replyToType: reply?.type,
      );
      if (_disposed) return;
      state = state.copyWith(isSending: false, clearReply: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  // ── Unsend ─────────────────────────────────────────────────────────────

  Future<void> unsendMessage(String messageId) async {
    final message = state.messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw Exception('Message not found'),
    );

    if (message.senderId != currentUserId) {
      throw Exception('Can only unsend your own messages');
    }

    final age = DateTime.now().difference(message.createdAt);
    if (age.inHours >= 1) {
      throw Exception('Can only unsend messages less than 1 hour old');
    }

    await _repo.unsendMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  // ── Delete message ─────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await _repo.deleteMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  // ── Pin / Unpin conversation ─────────────────────────────────────────

  Future<void> pinConversation() async {
    await _repo.pinConversation(
      conversationId: conversationId,
      userId: currentUserId,
    );
  }

  Future<void> unpinConversation() async {
    await _repo.unpinConversation(
      conversationId: conversationId,
      userId: currentUserId,
    );
  }

  // ── Delete conversation ────────────────────────────────────────────────

  Future<void> deleteConversation() async {
    await _repo.deleteConversation(
      conversationId: conversationId,
      userId: currentUserId,
    );
  }

  // ── Seen ───────────────────────────────────────────────────────────────

  void markAsSeen() {
    _repo.markMessagesAsSeen(conversationId, currentUserId);
  }

  @override
  void dispose() {
    _disposed = true;
    _isViewing = false;
    _subscription?.cancel();
    super.dispose();
  }
}
