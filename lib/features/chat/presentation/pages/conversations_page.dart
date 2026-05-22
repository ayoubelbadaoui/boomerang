import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/chat/presentation/widgets/conversation_tile.dart';
import 'package:boomerang/features/chat/presentation/widgets/recent_contacts_bar.dart';
import 'package:boomerang/features/chat/presentation/widgets/new_chat_sheet.dart';

class ConversationsPage extends ConsumerStatefulWidget {
  const ConversationsPage({super.key});

  static const routeName = '/conversations';

  @override
  ConsumerState<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends ConsumerState<ConversationsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  Future<void> _refreshConversations() async {
    ref.invalidate(conversationsStreamProvider);
    try {
      await ref.read(conversationsStreamProvider.future);
    } catch (_) {
      // Keep pull-to-refresh resilient even if the upstream stream errors.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(String conversationId) {
    if (_isSelectionMode) {
      _toggleSelection(conversationId);
      return;
    }
    context.push('/chat/$conversationId');
  }

  void _toggleSelection(String conversationId) {
    setState(() {
      if (_selectedIds.contains(conversationId)) {
        _selectedIds.remove(conversationId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(conversationId);
      }
    });
  }

  void _enterSelectionMode(String conversationId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(conversationId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll(List<ConversationEntity> conversations) {
    setState(() {
      if (_selectedIds.length == conversations.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(conversations.map((c) => c.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete chats?'),
            content: Text(
              count == 1
                  ? 'This conversation will be removed from your inbox.'
                  : '$count conversations will be removed from your inbox.',
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
    );

    if (confirmed != true || !mounted) return;

    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;

    final ids = _selectedIds.toList();
    _exitSelectionMode();
    await ref
        .read(chatRepoProvider)
        .deleteConversations(conversationIds: ids, userId: me.uid);
  }

  Future<void> _startNewConversation(String otherUid) async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    final repo = ref.read(chatRepoProvider);
    final convId = await repo.getOrCreateConversation([me.uid, otherUid]);
    if (mounted) _openChat(convId);
  }

  /// Inbox "back to parent" control: [Navigator.canPop] becomes true whenever
  /// *any* route is stacked above this page (including [ChatPage]), while this
  /// widget can still rebuild under the shell. Only show the control when this
  /// route is actually on top so it never appears over an open DM.
  bool _showInboxOuterBack(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    return Navigator.of(context).canPop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final convAsync = ref.watch(conversationsStreamProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final uid = currentUser?.uid ?? '';

    return Scaffold(
      appBar:
          _isSelectionMode
              ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                ),
                title: Text(
                  '${_selectedIds.length} selected',
                  style: theme.textTheme.titleLarge,
                ),
                actions: [
                  if (convAsync.hasValue)
                    IconButton(
                      icon: Icon(
                        _selectedIds.length == (convAsync.value?.length ?? 0)
                            ? Icons.deselect
                            : Icons.select_all,
                      ),
                      tooltip:
                          _selectedIds.length == (convAsync.value?.length ?? 0)
                              ? 'Deselect all'
                              : 'Select all',
                      onPressed: () => _selectAll(convAsync.value ?? []),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color:
                          _selectedIds.isNotEmpty
                              ? theme.colorScheme.error
                              : Colors.grey,
                    ),
                    onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                  ),
                ],
              )
              : AppBar(
                leading:
                    _showInboxOuterBack(context) ? const BackButton() : null,
                automaticallyImplyLeading: false,
                title: Text('Messages', style: theme.textTheme.titleLarge),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder:
                              (_) => DraggableScrollableSheet(
                                initialChildSize: 0.75,
                                minChildSize: 0.4,
                                maxChildSize: 0.92,
                                expand: false,
                                builder:
                                    (_, scrollController) =>
                                        const NewChatSheet(),
                              ),
                        ),
                  ),
                ],
              ),
      body: convAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (e, _) => Center(
              child: Padding(
                padding: EdgeInsets.all(32.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64.sp,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'No messages yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Start a conversation with someone!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        data: (conversations) {
          final filtered = _query.isEmpty ? conversations : conversations;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchBar(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
              ),
              if (!_isSelectionMode) ...[
                SizedBox(height: 16.h),
                _RecentSection(
                  conversations: conversations,
                  currentUid: uid,
                  onTap: _startNewConversation,
                ),
              ],
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Text('Messages', style: theme.textTheme.titleSmall),
              ),
              SizedBox(height: 4.h),
              Expanded(
                child: RefreshIndicator(
                  color: Colors.black,
                  onRefresh: _refreshConversations,
                  child:
                      filtered.isEmpty
                          ? _RefreshableEmptyState(theme: theme)
                          : _ConversationList(
                            conversations: filtered,
                            currentUid: uid,
                            searchQuery: _query,
                            onTap: _openChat,
                            isSelectionMode: _isSelectionMode,
                            selectedIds: _selectedIds,
                            onEnterSelection: _enterSelectionMode,
                          ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Search bar ──────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        height: 44.h,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(Icons.search, size: 20.sp, color: Colors.grey),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10.h),
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SizedBox(width: 12.w),
          ],
        ),
      ),
    );
  }
}

// ── Recent contacts section ─────────────────────────────────────────────

class _RecentSection extends ConsumerWidget {
  const _RecentSection({
    required this.conversations,
    required this.currentUid,
    required this.onTap,
  });

  final List<ConversationEntity> conversations;
  final String currentUid;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUids =
        conversations
            .map((c) => c.otherParticipantId(currentUid))
            .where((id) => id.isNotEmpty)
            .toSet()
            .take(10)
            .toList();

    final profiles = <UserProfile>[];
    for (final uid in otherUids) {
      final p = ref.watch(userProfileByIdProvider(uid)).value;
      if (p != null) profiles.add(p);
    }

    return RecentContactsBar(profiles: profiles, onTap: (p) => onTap(p.uid));
  }
}

// ── Conversation list ───────────────────────────────────────────────────

class _ConversationList extends ConsumerWidget {
  const _ConversationList({
    required this.conversations,
    required this.currentUid,
    required this.searchQuery,
    required this.onTap,
    this.isSelectionMode = false,
    this.selectedIds = const {},
    this.onEnterSelection,
  });

  final List<ConversationEntity> conversations;
  final String currentUid;
  final String searchQuery;
  final ValueChanged<String> onTap;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String>? onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sort: pinned conversations first, then by lastMessageAt (already sorted)
    final sorted = List<ConversationEntity>.from(conversations);
    sorted.sort((a, b) {
      final aPinned = a.isPinnedBy(currentUid);
      final bPinned = b.isPinnedBy(currentUid);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0; // preserve existing lastMessageAt ordering within each group
    });

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final conv = sorted[index];
        final otherId = conv.otherParticipantId(currentUid);
        if (otherId.isEmpty) return const SizedBox.shrink();
        final profile = ref.watch(userProfileByIdProvider(otherId)).value;

        if (searchQuery.isNotEmpty) {
          final name =
              (profile?.fullName ?? profile?.nickname ?? '').toLowerCase();
          if (!name.contains(searchQuery.toLowerCase())) {
            return const SizedBox.shrink();
          }
        }

        final isPinned = conv.isPinnedBy(currentUid);

        return ConversationTile(
          conversation: conv,
          otherUser: profile,
          currentUserId: currentUid,
          isPinned: isPinned,
          isSelectionMode: isSelectionMode,
          isSelected: selectedIds.contains(conv.id),
          onTap: () => onTap(conv.id),
          onLongPress:
              isSelectionMode
                  ? null
                  : () =>
                      _showConversationActions(context, ref, conv, isPinned),
        );
      },
    );
  }

  void _showConversationActions(
    BuildContext context,
    WidgetRef ref,
    ConversationEntity conv,
    bool isPinned,
  ) {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 16.h),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      isPinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin_rounded,
                      size: 22.sp,
                    ),
                    title: Text(
                      isPinned ? 'Unpin chat' : 'Pin chat',
                      style: theme.textTheme.bodyLarge,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
                    dense: true,
                    onTap: () {
                      Navigator.pop(context);
                      final repo = ref.read(chatRepoProvider);
                      if (isPinned) {
                        repo.unpinConversation(
                          conversationId: conv.id,
                          userId: currentUid,
                        );
                      } else {
                        repo.pinConversation(
                          conversationId: conv.id,
                          userId: currentUid,
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.checklist_rounded, size: 22.sp),
                    title: Text(
                      'Select chats',
                      style: theme.textTheme.bodyLarge,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
                    dense: true,
                    onTap: () {
                      Navigator.pop(context);
                      onEnterSelection?.call(conv.id);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      size: 22.sp,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete chat',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
                    dense: true,
                    onTap: () {
                      Navigator.pop(context);
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
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                      ).then((confirmed) {
                        if (confirmed == true) {
                          ref
                              .read(chatRepoProvider)
                              .deleteConversation(
                                conversationId: conv.id,
                                userId: currentUid,
                              );
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64.sp, color: Colors.grey),
          SizedBox(height: 16.h),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
          ),
          SizedBox(height: 8.h),
          Text(
            'Start a conversation with someone!',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _RefreshableEmptyState extends StatelessWidget {
  const _RefreshableEmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
        _EmptyState(theme: theme),
      ],
    );
  }
}
