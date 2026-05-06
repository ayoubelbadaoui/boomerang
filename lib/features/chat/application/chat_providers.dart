import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/domain/chat_repo.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/infrastructure/firestore_chat_repo.dart';
import 'package:boomerang/features/chat/application/chat_controller.dart';
import 'package:boomerang/features/chat/application/voice_message_playback_notifier.dart';

// ── Active conversation (suppresses push while chat is open) ────────────

final activeConversationProvider = StateProvider<String?>((ref) => null);

// ── Optimistic unread clearing ──────────────────────────────────────────
// Conversation IDs whose unread badge has been locally cleared before
// Firestore confirms the update.  Entries are removed after a short delay
// once the user leaves the chat, giving Firestore time to propagate.

final pendingSeenConversationIdsProvider =
    StateProvider<Set<String>>((ref) => {});

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

// ── Voice messages (single shared player app-wide) ──────────────────────

final voiceMessagePlaybackProvider = StateNotifierProvider<
    VoiceMessagePlaybackNotifier, VoiceMessagePlaybackState>(
  (ref) => VoiceMessagePlaybackNotifier(),
);

// ── DM permission gate ──────────────────────────────────────────────────
//
// Privacy rule: when the recipient runs a private account, only people they
// have accepted as followers (i.e. the current user already follows them)
// may direct-message them. Pending follow requests do NOT unlock the inbox.
// Public accounts remain freely messageable.

class CanDirectMessage {
  const CanDirectMessage({required this.allowed, required this.reason});

  final bool allowed;
  final String? reason;
}

final canDirectMessageProvider =
    Provider.family<CanDirectMessage, String>((ref, otherUid) {
  if (otherUid.isEmpty) {
    return const CanDirectMessage(allowed: true, reason: null);
  }
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null || me.uid == otherUid) {
    return const CanDirectMessage(allowed: true, reason: null);
  }
  final other = ref.watch(userProfileByIdProvider(otherUid)).value;
  if (other == null) {
    // Wait until the profile has loaded before locking the input. The
    // firestore_chat_repo guard catches the race.
    return const CanDirectMessage(allowed: true, reason: null);
  }
  if (!other.isPrivate) {
    return const CanDirectMessage(allowed: true, reason: null);
  }
  final iFollow =
      ref.watch(isFollowingStreamProvider(otherUid)).value ?? false;
  if (iFollow) {
    return const CanDirectMessage(allowed: true, reason: null);
  }
  return const CanDirectMessage(
    allowed: false,
    reason: 'This account is private. They have to accept your follow '
        'request before you can message them.',
  );
});

// ── Total unread badge across all conversations ─────────────────────────

final totalUnreadProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsStreamProvider).value ?? [];
  final uid = ref.watch(currentUserProfileProvider).value?.uid ?? '';
  if (uid.isEmpty) return 0;
  final pendingSeen = ref.watch(pendingSeenConversationIdsProvider);
  return conversations.fold<int>(
    0,
    (sum, c) {
      if (pendingSeen.contains(c.id)) return sum;
      return sum + c.unreadCountFor(uid);
    },
  );
});
