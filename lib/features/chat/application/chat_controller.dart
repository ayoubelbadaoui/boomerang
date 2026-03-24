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
  });

  final List<MessageEntity> messages;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final String? error;

  ChatState copyWith({
    List<MessageEntity>? messages,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSending,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      isSending: isSending ?? this.isSending,
      error: error,
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

  static const _pageSize = 20;

  void _init() {
    _subscription = _repo
        .streamMessages(conversationId, limit: _pageSize)
        .listen(
      (streamedMessages) {
        final paginatedOlder = state.messages
            .where((m) => !streamedMessages.any((sm) => sm.id == m.id))
            .toList();
        state = state.copyWith(
          messages: [...streamedMessages, ...paginatedOlder],
        );
      },
      onError: (Object e) {
        state = state.copyWith(error: e.toString());
      },
    );

    _repo.markMessagesAsSeen(conversationId, currentUserId);
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

      final existingIds = state.messages.map((m) => m.id).toSet();
      final fresh =
          older.where((m) => !existingIds.contains(m.id)).toList();

      state = state.copyWith(
        messages: [...state.messages, ...fresh],
        isLoadingMore: false,
        hasMore: older.length >= _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> sendMessage(
    String text, {
    MessageType type = MessageType.text,
  }) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(isSending: true, error: null);
    try {
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: text.trim(),
        type: type,
      );
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendImageMessage(String localPath) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      final url = await _repo.uploadChatImage(conversationId, localPath);
      await _repo.sendMessage(
        conversationId,
        senderId: currentUserId,
        text: url,
        type: MessageType.image,
      );
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  void markAsSeen() {
    _repo.markMessagesAsSeen(conversationId, currentUserId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
