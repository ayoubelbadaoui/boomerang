import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:boomerang/features/chat/presentation/widgets/message_bubble.dart';
import 'package:boomerang/features/chat/presentation/widgets/chat_input_field.dart';
import 'package:boomerang/features/chat/presentation/widgets/date_separator.dart';
import 'package:boomerang/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:boomerang/features/profile/application/follow_controller.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  final _inputKey = GlobalKey<ChatInputFieldState>();
  bool _emojiOpen = false;
  ProviderContainer? _container;

  /// Stable GlobalKey per message ID. Re-used across rebuilds so we can
  /// (a) read each bubble's real RenderBox.size and (b) call
  /// [Scrollable.ensureVisible] on its BuildContext.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Message currently being highlighted after a navigation tap.
  String? _highlightedMessageId;

  /// Identifies the in-flight navigation. New taps overwrite this token so
  /// stale work bails out instead of fighting the new animation.
  Object? _navToken;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_container != null) return;
    _container = ProviderScope.containerOf(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _container!.read(activeConversationProvider.notifier).state =
          widget.conversationId;
      _container!
          .read(pendingSeenConversationIdsProvider.notifier)
          .update((ids) => {...ids, widget.conversationId});
      _container!
          .read(chatControllerProvider(widget.conversationId).notifier)
          .setViewing(true);
    });
  }

  @override
  void dispose() {
    final container = _container;
    final convId = widget.conversationId;

    Future(() {
      try {
        container
            ?.read(chatControllerProvider(convId).notifier)
            .setViewing(false);
        container?.read(activeConversationProvider.notifier).state = null;
      } catch (_) {}
    });

    Future.delayed(const Duration(seconds: 2), () {
      try {
        container
            ?.read(pendingSeenConversationIdsProvider.notifier)
            .update((ids) => Set<String>.from(ids)..remove(convId));
      } catch (_) {}
    });

    _navToken = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(chatControllerProvider(widget.conversationId).notifier)
          .loadMore();
    }
  }

  void _toggleEmoji() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _inputKey.currentState?.focusNode.requestFocus();
    } else {
      _inputKey.currentState?.focusNode.unfocus();
      setState(() => _emojiOpen = true);
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    final controller = _inputKey.currentState?.controller;
    if (controller == null) return;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.baseOffset < 0 ? text.length : selection.baseOffset;
    final newText = text.replaceRange(start, start, emoji.emoji);
    controller
      ..text = newText
      ..selection = TextSelection.collapsed(offset: start + emoji.emoji.length);
  }

  void _showMessageActions(MessageEntity message, bool isMine) {
    if (message.isUnsent) return;

    final conversations =
        ref.read(conversationsStreamProvider).value ?? const [];
    final myUid = ref.read(currentUserProfileProvider).value?.uid ?? '';
    final conversation = conversations.cast<ConversationEntity?>().firstWhere(
      (c) => c?.id == widget.conversationId,
      orElse: () => null,
    );
    final otherUid = conversation?.otherParticipantId(myUid) ?? '';
    final canReply =
        otherUid.isEmpty
            ? true
            : ref.read(canDirectMessageProvider(otherUid)).allowed;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder:
          (_) => MessageActionsSheet(
            message: message,
            isMine: isMine,
            canReply: canReply,
            onReply: () {
              ref
                  .read(chatControllerProvider(widget.conversationId).notifier)
                  .setReplyTo(message);
              _inputKey.currentState?.focusNode.requestFocus();
            },
            onUnsend: () {
              ref
                  .read(chatControllerProvider(widget.conversationId).notifier)
                  .unsendMessage(message.id);
            },
            onDelete: () {
              ref
                  .read(chatControllerProvider(widget.conversationId).notifier)
                  .deleteMessage(message.id);
            },
          ),
    );
  }

  /// Navigate to the message referenced by [messageId].
  ///
  /// ID is the source of truth: we never trust a stale index or a fixed
  /// pixel offset. The algorithm is:
  ///   1. If the target isn't in the loaded window, page older messages
  ///      until it appears (bounded).
  ///   2. Coarse jump using the *measured* average bubble height of
  ///      currently rendered messages, so the target enters the
  ///      ListView's lazy build window.
  ///   3. Once the target's RenderBox is mounted, finalize with
  ///      [Scrollable.ensureVisible] (alignment 0.5 → centered).
  ///   4. Briefly highlight the target for orientation.
  ///   5. If pagination exhausts without finding it (e.g. deleted),
  ///      surface a non-blocking snackbar instead of silently failing.
  Future<void> _scrollToMessage(String messageId) async {
    final token = Object();
    _navToken = token;
    bool cancelled() => !mounted || _navToken != token;

    final notifier = ref.read(
      chatControllerProvider(widget.conversationId).notifier,
    );

    final inWindow = ref
        .read(chatControllerProvider(widget.conversationId))
        .messages
        .any((m) => m.id == messageId);

    if (!inWindow) {
      final found = await notifier.loadUntilContains(messageId);
      if (cancelled()) return;
      if (!found) {
        _showNavigationFallback();
        return;
      }
    }

    await _coarseAndEnsureVisible(messageId, token);
    if (cancelled()) return;

    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      if (_highlightedMessageId == messageId && _navToken == token) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _coarseAndEnsureVisible(String messageId, Object token) async {
    bool cancelled() => !mounted || _navToken != token;

    const maxIterations = 4;
    for (int iter = 0; iter < maxIterations; iter++) {
      if (cancelled()) return;

      final renderObject =
          _messageKeys[messageId]?.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final ctx = _messageKeys[messageId]!.currentContext!;
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
        return;
      }

      final state = ref.read(chatControllerProvider(widget.conversationId));
      final items = _buildItemsWithSeparators(state.messages);
      final targetItemIndex = items.indexWhere(
        (it) => it is MessageEntity && it.id == messageId,
      );
      if (targetItemIndex == -1) return;

      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final avg = _estimateAverageItemHeight();
      final estimated = (targetItemIndex * avg).clamp(
        0.0,
        position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        estimated,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      if (cancelled()) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Mean height of currently-mounted message bubbles. We deliberately
  /// sample real RenderBoxes instead of guessing per type, so mixed text /
  /// media / audio / unsent cells all contribute. Falls back to a
  /// conservative constant before anything has measured.
  double _estimateAverageItemHeight() {
    double total = 0;
    int count = 0;
    for (final key in _messageKeys.values) {
      final ro = key.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        total += ro.size.height;
        count++;
      }
    }
    if (count == 0) return 80.0;
    return total / count;
  }

  void _showNavigationFallback() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Original message is no longer available.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openSharedPost(String boomerangId) {
    context.push('/boomerang/$boomerangId');
  }

  void _confirmDeleteChat() {
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete chat?'),
            content: const Text(
              'This conversation will be removed from your inbox.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    ).then((confirmed) async {
      if (confirmed == true) {
        await ref
            .read(chatControllerProvider(widget.conversationId).notifier)
            .deleteConversation();
        if (mounted) context.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final uid = currentUser?.uid ?? '';

    final conversation = _resolveConversation(ref);
    final otherUid = conversation?.otherParticipantId(uid) ?? '';
    final otherProfile =
        otherUid.isNotEmpty
            ? ref.watch(userProfileByIdProvider(otherUid)).value
            : null;

    final permission =
        otherUid.isNotEmpty
            ? ref.watch(canDirectMessageProvider(otherUid))
            : const CanDirectMessage(allowed: true, reason: null);

    return Scaffold(
      appBar: _ChatAppBar(profile: otherProfile, onDelete: _confirmDeleteChat),
      body: Column(
        children: [
          if (otherUid.isNotEmpty) _FollowBackBanner(otherUid: otherUid),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _inputKey.currentState?.focusNode.unfocus();
                if (_emojiOpen) setState(() => _emojiOpen = false);
              },
              child: _MessageList(
                messages: chatState.messages,
                currentUid: uid,
                isLoadingMore: chatState.isLoadingMore,
                scrollController: _scrollController,
                onMessageLongPress: _showMessageActions,
                onReplyTap: _scrollToMessage,
                onSharedPostTap: _openSharedPost,
                otherProfile: otherProfile,
                currentProfile: currentUser,
                keyFor: _keyFor,
                highlightedMessageId: _highlightedMessageId,
              ),
            ),
          ),
          if (!permission.allowed)
            _DirectMessageLockBanner(reason: permission.reason)
          else
            ChatInputField(
              key: _inputKey,
              isSending: chatState.isSending,
              emojiOpen: _emojiOpen,
              onToggleEmoji: _toggleEmoji,
              replyingTo: chatState.replyingTo,
              replyToSenderName: _senderNameForReply(
                chatState.replyingTo,
                uid,
                currentUser,
                otherProfile,
              ),
              onClearReply:
                  () =>
                      ref
                          .read(
                            chatControllerProvider(
                              widget.conversationId,
                            ).notifier,
                          )
                          .clearReply(),
              onSendText:
                  (text) => ref
                      .read(
                        chatControllerProvider(widget.conversationId).notifier,
                      )
                      .sendMessage(text),
              onSendImage:
                  (path) => ref
                      .read(
                        chatControllerProvider(widget.conversationId).notifier,
                      )
                      .sendImageMessage(path),
              onSendGif:
                  (url) => ref
                      .read(
                        chatControllerProvider(widget.conversationId).notifier,
                      )
                      .sendGifMessage(url),
              onSendAudio:
                  (path, durationMs) => ref
                      .read(
                        chatControllerProvider(widget.conversationId).notifier,
                      )
                      .sendAudioMessage(path, durationMs),
            ),
          if (_emojiOpen && permission.allowed)
            SizedBox(
              height: 280.h,
              child: EmojiPicker(
                onEmojiSelected: _onEmojiSelected,
                onBackspacePressed: () {
                  final controller = _inputKey.currentState?.controller;
                  if (controller == null || controller.text.isEmpty) return;
                  final text = controller.text;
                  controller
                    ..text = text.characters.skipLast(1).toString()
                    ..selection = TextSelection.collapsed(
                      offset: controller.text.length,
                    );
                },
                config: Config(
                  height: 280.h,
                  emojiViewConfig: EmojiViewConfig(
                    columns: 8,
                    emojiSizeMax: 28.sp,
                    backgroundColor: Colors.white,
                  ),
                  categoryViewConfig: const CategoryViewConfig(
                    indicatorColor: Colors.black,
                    iconColorSelected: Colors.black,
                    iconColor: Colors.grey,
                    backgroundColor: Colors.white,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    enabled: false,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: Colors.white,
                    buttonIconColor: Colors.black,
                    hintText: 'Search emoji...',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ConversationEntity? _resolveConversation(WidgetRef ref) {
    final conversations = ref.watch(conversationsStreamProvider).value ?? [];
    return conversations.cast<ConversationEntity?>().firstWhere(
      (c) => c?.id == widget.conversationId,
      orElse: () => null,
    );
  }

  String? _senderNameForReply(
    MessageEntity? reply,
    String myUid,
    UserProfile? me,
    UserProfile? other,
  ) {
    if (reply == null) return null;
    if (reply.senderId == myUid) return 'You';
    return other?.fullName ?? other?.nickname ?? '';
  }

  List<Object> _buildItemsWithSeparators(List<MessageEntity> messages) {
    final items = <Object>[];
    for (int i = 0; i < messages.length; i++) {
      items.add(messages[i]);
      final isLast = i == messages.length - 1;
      if (isLast ||
          !_sameDay(messages[i].createdAt, messages[i + 1].createdAt)) {
        items.add(messages[i].createdAt);
      }
    }
    return items;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── App bar ─────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({required this.profile, required this.onDelete});

  final UserProfile? profile;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      leading: const BackButton(),
      title: GestureDetector(
        onTap:
            profile != null
                ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OtherUserProfilePage(userId: profile!.uid),
                  ),
                )
                : null,
        child: Text(
          profile?.fullName ?? profile?.nickname ?? '',
          style: theme.textTheme.titleMedium,
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (value) {
            if (value == 'delete') onDelete();
          },
          itemBuilder:
              (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Delete chat'),
                    ],
                  ),
                ),
              ],
        ),
      ],
    );
  }
}

// ── Follow-state banner ─────────────────────────────────────────────────
//
// Shows a small bar above the message list whenever the current user is
// NOT following the other user, with a context-aware action:
//
//   * They already follow me        → "Follow back"
//   * I sent a follow request       → "Pending" (tap to cancel)
//   * Other account is private      → "Request"
//   * Otherwise                     → "Follow"
//
// Disappears as soon as we're following them (or have been accepted).

class _FollowBackBanner extends ConsumerStatefulWidget {
  const _FollowBackBanner({required this.otherUid});
  final String otherUid;

  @override
  ConsumerState<_FollowBackBanner> createState() => _FollowBackBannerState();
}

class _FollowBackBannerState extends ConsumerState<_FollowBackBanner> {
  Future<void> _onPressed({
    required FollowState currentState,
    required bool targetIsPrivate,
  }) async {
    try {
      await ref
          .read(followFlowControllerProvider.notifier)
          .toggleRelationship(
            targetUserId: widget.otherUid,
            targetIsPrivate: targetIsPrivate,
            currentState: currentState,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(followStateProvider(widget.otherUid));
    if (state == FollowState.approved) return const SizedBox.shrink();
    final loading = ref.watch(isFollowActionInFlightProvider(widget.otherUid));

    final theyFollowMe =
        ref.watch(isFollowedByProvider(widget.otherUid)).value ?? false;
    final requested = state == FollowState.requested;

    final otherProfile =
        ref.watch(userProfileByIdProvider(widget.otherUid)).value;
    final isPrivate = otherProfile?.isPrivate ?? false;
    final name =
        otherProfile?.fullName ?? otherProfile?.nickname ?? 'This user';

    final String headline;
    final String buttonLabel;
    if (theyFollowMe) {
      headline = '$name follows you';
      buttonLabel = requested ? 'Requested' : 'Follow';
    } else if (requested) {
      headline = 'Follow request sent';
      buttonLabel = 'Requested';
    } else {
      headline = isPrivate ? '$name has a private account' : 'Say hi to $name';
      buttonLabel = 'Follow';
    }

    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1, size: 18.sp, color: Colors.black54),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              headline,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8.w),
          SizedBox(
            height: 32.h,
            child: ElevatedButton(
              onPressed:
                  loading
                      ? null
                      : () => _onPressed(
                        currentState: state,
                        targetIsPrivate: isPrivate,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    requested ? Colors.white : theme.colorScheme.primary,
                foregroundColor: requested ? Colors.black87 : Colors.white,
                side:
                    requested
                        ? const BorderSide(color: Colors.black26)
                        : BorderSide.none,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                shape: const StadiumBorder(),
                textStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child:
                  loading
                      ? SizedBox(
                        width: 14.w,
                        height: 14.w,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: requested ? Colors.black54 : Colors.white,
                        ),
                      )
                      : Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Direct-message permission lock ──────────────────────────────────────

class _DirectMessageLockBanner extends StatelessWidget {
  const _DirectMessageLockBanner({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16.w,
        16.h,
        16.w,
        16.h + (bottomSafe > 0 ? bottomSafe : 0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 20.sp, color: Colors.black54),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              reason ?? 'You can\'t reply to this conversation right now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message list with date separators ───────────────────────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.currentUid,
    required this.isLoadingMore,
    required this.scrollController,
    required this.onMessageLongPress,
    required this.onReplyTap,
    required this.onSharedPostTap,
    required this.keyFor,
    required this.highlightedMessageId,
    this.otherProfile,
    this.currentProfile,
  });

  final List<MessageEntity> messages;
  final String currentUid;
  final bool isLoadingMore;
  final ScrollController scrollController;
  final void Function(MessageEntity msg, bool isMine) onMessageLongPress;
  final void Function(String messageId) onReplyTap;
  final void Function(String boomerangId) onSharedPostTap;
  final UserProfile? otherProfile;
  final UserProfile? currentProfile;

  /// Stable per-message-ID GlobalKey provider, owned by the parent. We
  /// attach the key to each bubble so the navigation pass can locate the
  /// real RenderBox.
  final GlobalKey Function(String messageId) keyFor;
  final String? highlightedMessageId;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Say hello!',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
        ),
      );
    }

    final items = _buildItemsWithSeparators();

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (isLoadingMore && index == items.length) {
          return Padding(
            padding: EdgeInsets.all(16.h),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = items[index];
        if (item is DateTime) {
          return DateSeparator(date: item);
        }
        final message = item as MessageEntity;
        final isMine = message.senderId == currentUid;

        String? replySenderName;
        if (message.hasReply) {
          if (message.replyToSenderId == currentUid) {
            replySenderName = 'You';
          } else {
            replySenderName =
                otherProfile?.fullName ?? otherProfile?.nickname ?? '';
          }
        }

        return MessageBubble(
          key: keyFor(message.id),
          message: message,
          isMine: isMine,
          replyToSenderName: replySenderName,
          highlighted: highlightedMessageId == message.id,
          onLongPress: () => onMessageLongPress(message, isMine),
          onReplyTap:
              message.hasReply
                  ? () => onReplyTap(message.replyToMessageId!)
                  : null,
          onSharedPostTap:
              message.isSharedPost && message.sharedPostId != null
                  ? () => onSharedPostTap(message.sharedPostId!)
                  : null,
        );
      },
    );
  }

  List<Object> _buildItemsWithSeparators() {
    final items = <Object>[];
    for (int i = 0; i < messages.length; i++) {
      items.add(messages[i]);
      final isLast = i == messages.length - 1;
      if (isLast ||
          !_sameDay(messages[i].createdAt, messages[i + 1].createdAt)) {
        items.add(messages[i].createdAt);
      }
    }
    return items;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
