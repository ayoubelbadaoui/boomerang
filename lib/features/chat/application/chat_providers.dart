import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/domain/chat_repo.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/infrastructure/firestore_chat_repo.dart';
import 'package:boomerang/features/chat/application/chat_controller.dart';

// ── Active conversation (suppresses push while chat is open) ────────────

final activeConversationProvider = StateProvider<String?>((ref) => null);

// ── Repository ──────────────────────────────────────────────────────────

final chatRepoProvider = Provider<ChatRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final storage = ref.watch(storageProvider);
  return FirestoreChatRepo(fs, storage);
});

// ── Conversation list (real-time) ───────────────────────────────────────

final conversationsStreamProvider =
    StreamProvider<List<ConversationEntity>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref
      .watch(chatRepoProvider)
      .streamConversations(user.uid)
      .transform(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) => sink.add(data),
          handleError: (error, stackTrace, sink) {
            debugPrint('conversationsStream error: $error');
            sink.add([]);
          },
        ),
      );
});

// ── Per-conversation chat controller ────────────────────────────────────

final chatControllerProvider =
    StateNotifierProvider.family<ChatController, ChatState, String>(
  (ref, conversationId) {
    final repo = ref.watch(chatRepoProvider);
    final user = ref.watch(currentUserProfileProvider).value;
    return ChatController(
      repo: repo,
      conversationId: conversationId,
      currentUserId: user?.uid ?? '',
    );
  },
);

// ── Total unread badge across all conversations ─────────────────────────

final totalUnreadProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsStreamProvider).value ?? [];
  final uid = ref.watch(currentUserProfileProvider).value?.uid ?? '';
  if (uid.isEmpty) return 0;
  return conversations.fold<int>(
    0,
    (sum, c) => sum + c.unreadCountFor(uid),
  );
});
