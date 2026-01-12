import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/widgets/avatar.dart';

class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});

  static const String routeName = '/inbox_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final uid = me?.uid;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'All Activity',
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: Colors.black),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.send, color: Colors.black),
          ),
        ],
      ),
      body:
          uid == null
              ? const Center(child: Text('Sign in to see notifications'))
              : RefreshIndicator(
                onRefresh: () async {},
                child: StreamBuilder(
                  stream: ref.watch(notificationsRepoProvider).watch(uid),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    final items =
                        docs.map((doc) {
                          final d = doc.data();
                          final type = (d['type'] ?? '') as String;
                          final rawTitle = (d['actorName'] ?? '') as String;
                          final senderId =
                              ((d['senderId'] ?? d['actorUserId']) ?? '')
                                  as String;
                          final title =
                              rawTitle.trim().isNotEmpty
                                  ? rawTitle
                                  : (senderId.isNotEmpty
                                      ? 'user_${senderId.substring(0, senderId.length.clamp(0, 6))}'
                                      : 'User');
                          final avatar = d['actorAvatar'] as String?;
                          final ts = d['createdAt'];
                          final createdAt =
                              ts is Timestamp ? ts.toDate() : DateTime.now();
                          String subtitle = '';
                          String? thumb;
                          String? action;
                          _ItemType itemType = _ItemType.other;
                          final read = (d['read'] ?? false) as bool;
                          if (type == 'follow') {
                            subtitle = 'Started following you';
                            action = 'Follow Back';
                            itemType = _ItemType.follow;
                          } else if (type == 'like') {
                            subtitle = 'Liked your video';
                            thumb = d['boomerangImage'] as String?;
                            itemType = _ItemType.like;
                          } else if (type == 'comment') {
                            subtitle = 'Commented on your video';
                            thumb = d['boomerangImage'] as String?;
                            itemType = _ItemType.comment;
                          } else {
                            subtitle = 'Activity';
                          }
                          return _Item(
                            id: doc.id,
                            avatar:
                                avatar ??
                                'https://picsum.photos/seed/a${title.hashCode}/100/100',
                            title: title,
                            subtitle: subtitle,
                            trailingThumb: thumb,
                            actionLabel: action,
                            createdAt: createdAt,
                            actorId: senderId,
                            boomerangId: d['boomerangId'] as String?,
                            commentId: d['commentId'] as String?,
                            type: itemType,
                            read: read,
                          );
                        }).toList();

                    if (items.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('No notifications yet')),
                        ],
                      );
                    }

                    final sections = _groupSections(items);
                    final children = <Widget>[];
                    for (final section in sections) {
                      children.add(
                        Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
                          child: Text(
                            section.label,
                            style: TextStyle(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );
                      for (final item in section.items) {
                        children.add(
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: _ActivityTile(item: item),
                          ),
                        );
                      }
                    }

                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(bottom: 24.h),
                      itemCount: children.length,
                      itemBuilder: (_, i) => children[i],
                    );
                  },
                ),
              ),
    );
  }
}

class _Item {
  _Item({
    required this.id,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.actorId,
    required this.type,
    required this.read,
    this.trailingThumb,
    this.actionLabel,
    this.boomerangId,
    this.commentId,
  });
  final String id;
  final String avatar;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String actorId;
  final _ItemType type;
  final bool read;
  final String? boomerangId;
  final String? commentId;
  final String? trailingThumb;
  final String? actionLabel;
}

enum _ItemType { follow, like, comment, other }

class _Section {
  _Section(this.label, this.items);
  final String label;
  final List<_Item> items;
}

List<_Section> _groupSections(List<_Item> items) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final startOfWeek = today.subtract(Duration(days: now.weekday % 7));

  final todayItems = <_Item>[];
  final yesterdayItems = <_Item>[];
  final weekItems = <_Item>[];
  final earlierItems = <_Item>[];

  for (final item in items) {
    final d = DateTime(
      item.createdAt.year,
      item.createdAt.month,
      item.createdAt.day,
    );
    if (d.isAtSameMomentAs(today)) {
      todayItems.add(item);
    } else if (d.isAtSameMomentAs(yesterday)) {
      yesterdayItems.add(item);
    } else if (d.isAfter(startOfWeek)) {
      weekItems.add(item);
    } else {
      earlierItems.add(item);
    }
  }

  final sections = <_Section>[];
  if (todayItems.isNotEmpty) sections.add(_Section('Today', todayItems));
  if (yesterdayItems.isNotEmpty)
    sections.add(_Section('Yesterday', yesterdayItems));
  if (weekItems.isNotEmpty) sections.add(_Section('This Week', weekItems));
  if (earlierItems.isNotEmpty) sections.add(_Section('Earlier', earlierItems));
  return sections;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final _Item item;
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return InkWell(
          onTap: () => _handleTap(context, ref, item),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _openProfile(context, ref, item),
                  customBorder: const CircleBorder(),
                  child: AppAvatar(url: item.avatar, size: 60.r),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _openProfile(context, ref, item),
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight:
                                item.read ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.subtitle,
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 14.sp,
                                height: 1.2,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            _timeAgo(item.createdAt),
                            style: TextStyle(
                              color: Colors.black45,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                if (item.actionLabel != null)
                  _FollowButton(
                    label: item.actionLabel!,
                    onPressed: () => _followBack(ref, item.actorId),
                  )
                else if (item.trailingThumb != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: Image.network(
                      item.trailingThumb!,
                      width: 56.r,
                      height: 56.r,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        backgroundColor: const Color(0xFFE3E3E3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _handleTap(BuildContext context, WidgetRef ref, _Item item) async {
  switch (item.type) {
    case _ItemType.follow:
      await _openProfile(context, ref, item);
      break;
    case _ItemType.like:
    case _ItemType.comment:
      await _openPost(context, ref, item);
      break;
    case _ItemType.other:
      break;
  }
  await _markRead(ref, item);
}

Future<void> _openProfile(
  BuildContext context,
  WidgetRef ref,
  _Item item,
) async {
  if (item.actorId.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) {
      return ProfilePreviewSheet(
        userId: item.actorId,
        handle: '@${item.title.replaceAll(' ', '').toLowerCase()}',
        avatarUrl: item.avatar,
        subtitle: item.subtitle,
      );
    },
  );
}

Future<void> _markRead(WidgetRef ref, _Item item) async {
  final me = ref.read(currentUserProfileProvider).value;
  if (me == null || item.read) return;
  await ref
      .read(notificationsRepoProvider)
      .markRead(uid: me.uid, notificationId: item.id);
}

Future<void> _followBack(WidgetRef ref, String actorId) async {
  if (actorId.isEmpty) return;
  await ref.read(followRepoProvider).follow(actorId);
}

Future<void> _openPost(BuildContext context, WidgetRef ref, _Item item) async {
  if (item.boomerangId == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Post not available')));
    return;
  }
  final repo = ref.read(boomerangRepoProvider);
  final data = await repo.fetchBoomerangById(item.boomerangId!);
  if (data == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post not found')));
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => BoomerangPagerPage(initialId: data.$1, initialData: data.$2),
    ),
  );
}

String _timeAgo(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays == 1) return '1d';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 4) return '${weeks}w';
  final months = (diff.inDays / 30).floor();
  if (months < 12) return '${months}mo';
  final years = (diff.inDays / 365).floor();
  return '${years}y';
}
