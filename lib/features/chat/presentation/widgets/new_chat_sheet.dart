import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';

class NewChatSheet extends ConsumerStatefulWidget {
  const NewChatSheet({super.key});

  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _loadingUserId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startChat(String otherUid) async {
    if (_loadingUserId != null) return;
    setState(() => _loadingUserId = otherUid);
    try {
      final me = ref.read(currentUserProfileProvider).value;
      if (me == null) return;
      final repo = ref.read(chatRepoProvider);
      final convId = await repo.getOrCreateConversation([me.uid, otherUid]);
      if (!mounted) return;
      Navigator.pop(context);
      context.push('/chat/$convId');
    } finally {
      if (mounted) setState(() => _loadingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProfileProvider).value;
    final uid = me?.uid ?? '';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              'New Message',
              style: theme.textTheme.titleLarge,
            ),
            SizedBox(height: 16.h),
            _SearchField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
            ),
            SizedBox(height: 12.h),
            Divider(height: 1.h, color: Colors.black12),
            SizedBox(height: 8.h),
            Expanded(
              child: uid.isEmpty
                  ? const SizedBox.shrink()
                  : _FollowingList(
                      uid: uid,
                      query: _query,
                      loadingUserId: _loadingUserId,
                      onTap: _startChat,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
                hintText: 'Search people',
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
    );
  }
}

// ── Following list ──────────────────────────────────────────────────────

class _FollowingList extends ConsumerWidget {
  const _FollowingList({
    required this.uid,
    required this.query,
    required this.loadingUserId,
    required this.onTap,
  });

  final String uid;
  final String query;
  final String? loadingUserId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(followRepoProvider).watchFollowing(uid);
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final theme = Theme.of(context);

    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allDocs = snapshot.data!.docs;
        final docs = blockedSet.isEmpty
            ? allDocs
            : allDocs
                .where((d) =>
                    !blockedSet.contains((d.data()['userId'] ?? '') as String))
                .toList();
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 80.h),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 56.sp, color: Colors.grey),
                  SizedBox(height: 12.h),
                  Text(
                    'No following yet',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Follow people to start a conversation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final filtered = query.isEmpty
            ? docs
            : docs.where((d) {
                final name =
                    (d.data()['userName'] ?? '').toString().toLowerCase();
                return name.contains(query.toLowerCase());
              }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'No results for "$query"',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 24.h),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final d = filtered[i].data();
            final userId = (d['userId'] ?? '') as String;
            final name = (d['userName'] ?? 'User') as String;
            final avatar = d['userAvatar'] as String?;
            final isLoading = loadingUserId == userId;

            return _UserTile(
              userId: userId,
              name: name,
              avatarFallback: avatar,
              isLoading: isLoading,
              onTap: () => onTap(userId),
            );
          },
        );
      },
    );
  }
}

// ── Single user tile ────────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.userId,
    required this.name,
    required this.avatarFallback,
    required this.isLoading,
    required this.onTap,
  });

  final String userId;
  final String name;
  final String? avatarFallback;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = '@${name.replaceAll(' ', '_').toLowerCase()}';

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
        child: Row(
          children: [
            LiveAvatar(userId: userId, fallbackUrl: avatarFallback, size: 48.r),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  SizedBox(height: 2.h),
                  Text(
                    handle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 20.w,
                height: 20.w,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.chat_bubble_outline,
                size: 20.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
