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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(String conversationId) {
    context.push('/chat/$conversationId');
  }

  Future<void> _startNewConversation(String otherUid) async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    final repo = ref.read(chatRepoProvider);
    final convId = await repo.getOrCreateConversation([me.uid, otherUid]);
    if (mounted) _openChat(convId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final convAsync = ref.watch(conversationsStreamProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final uid = currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
        automaticallyImplyLeading: false,
        title: Text('Messages', style: theme.textTheme.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.75,
                minChildSize: 0.4,
                maxChildSize: 0.92,
                expand: false,
                builder: (_, scrollController) => const NewChatSheet(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {},
          ),
        ],
      ),
      body: convAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: EdgeInsets.all(32.w),
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
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (conversations) {
          final filtered = _query.isEmpty
              ? conversations
              : conversations; // real filter applied below via profile names

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchBar(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
              ),
              SizedBox(height: 16.h),
              _RecentSection(
                conversations: conversations,
                currentUid: uid,
                onTap: _startNewConversation,
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Text('Messages', style: theme.textTheme.titleSmall),
              ),
              SizedBox(height: 4.h),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(theme: theme)
                    : _ConversationList(
                        conversations: filtered,
                        currentUid: uid,
                        searchQuery: _query,
                        onTap: _openChat,
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
            Icon(Icons.tune, size: 20.sp, color: Colors.grey),
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
    final otherUids = conversations
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

    return RecentContactsBar(
      profiles: profiles,
      onTap: (p) => onTap(p.uid),
    );
  }
}

// ── Conversation list ───────────────────────────────────────────────────

class _ConversationList extends ConsumerWidget {
  const _ConversationList({
    required this.conversations,
    required this.currentUid,
    required this.searchQuery,
    required this.onTap,
  });

  final List<ConversationEntity> conversations;
  final String currentUid;
  final String searchQuery;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
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

        return ConversationTile(
          conversation: conv,
          otherUser: profile,
          currentUserId: currentUid,
          onTap: () => onTap(conv.id),
        );
      },
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
