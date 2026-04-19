import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/widgets/live_avatar.dart';

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
                color: Colors.black,
                onRefresh: () async {
                  ref.invalidate(notificationsStreamProvider(uid));
                },
                child: ref
                    .watch(notificationsStreamProvider(uid))
                    .when(
                      loading:
                          () =>
                              const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (snapshot) {
                        final docs = snapshot.docs;
                        final items =
                            docs.map((doc) {
                              final d = doc.data();
                              final type = (d['type'] ?? '') as String;
                              final rawTitle = (d['actorName'] ?? '') as String;
                              final status = (d['status'] ?? '') as String;
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
                                  ts is Timestamp
                                      ? ts.toDate()
                                      : DateTime.now();
                              String subtitle = '';
                              String? thumb;
                              String? action;
                              _ItemType itemType = _ItemType.other;
                              final read = (d['read'] ?? false) as bool;
                              if (type == 'follow') {
                                subtitle = 'Started following you';
                                action = 'Follow Back';
                                itemType = _ItemType.follow;
                              } else if (type == 'follow_request') {
                                subtitle = 'Requested to follow you';
                                itemType = _ItemType.followRequest;
                              } else if (type == 'like') {
                                subtitle = 'Liked your boomerang';
                                thumb = d['boomerangImage'] as String?;
                                itemType = _ItemType.like;
                              } else if (type == 'comment') {
                                subtitle = 'Commented on your boomerang';
                                thumb = d['boomerangImage'] as String?;
                                itemType = _ItemType.comment;
                              } else if (type == 'reply') {
                                subtitle = 'Replied to your comment';
                                thumb = d['boomerangImage'] as String?;
                                itemType = _ItemType.reply;
                              } else {
                                subtitle = 'Activity';
                              }
                              return _Item(
                                id: doc.id,
                                avatar: (avatar != null && avatar.isNotEmpty)
                                    ? avatar
                                    : '',
                                title: title,
                                subtitle: subtitle,
                                trailingThumb: thumb,
                                actionLabel: action,
                                createdAt: createdAt,
                                actorId: senderId,
                                boomerangId: d['boomerangId'] as String?,
                                commentId: d['commentId'] as String?,
                                parentCommentId:
                                    d['parentCommentId'] as String?,
                                replyId: d['replyId'] as String?,
                                type: itemType,
                                read: read,
                                status: status,
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
                              padding: EdgeInsets.fromLTRB(
                                16.w,
                                12.h,
                                16.w,
                                4.h,
                              ),
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
    this.status,
    this.trailingThumb,
    this.actionLabel,
    this.boomerangId,
    this.commentId,
    this.parentCommentId,
    this.replyId,
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
  final String? parentCommentId;
  final String? replyId;
  final String? trailingThumb;
  final String? actionLabel;
  final String? status;
}

enum _ItemType { follow, followRequest, like, comment, reply, other }

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
  if (yesterdayItems.isNotEmpty) {
    sections.add(_Section('Yesterday', yesterdayItems));
  }
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
        final isFollowing =
            ref.watch(isFollowingStreamProvider(item.actorId)).value ?? false;
        final isPendingRequest =
            item.type == _ItemType.followRequest &&
            (item.status?.isEmpty == true || item.status == 'pending') &&
            !item.read &&
            !isFollowing;

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
                  child: LiveAvatar(userId: item.actorId, fallbackUrl: item.avatar, size: 60.r),
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
                if (isPendingRequest)
                  _FollowRequestActions(item: item)
                else if (item.type == _ItemType.follow)
                  _FollowBackButton(item: item)
                else if (item.trailingThumb != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6.r),
                    child: Image.network(
                      item.trailingThumb!,
                      width: 48.r,
                      height: 48.r,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: 150,
                      cacheHeight: 150,
                      frameBuilder: (_, child, frame, sync) {
                        if (sync) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 48.r,
                          height: 48.r,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: 48.r,
                        height: 48.r,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.grey.shade400,
                          size: 20,
                        ),
                      ),
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

class _FollowBackButton extends ConsumerWidget {
  const _FollowBackButton({required this.item});
  final _Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.actorId.isEmpty) return const SizedBox.shrink();

    final isFollowingAsync = ref.watch(isFollowingStreamProvider(item.actorId));
    final isFollowing = isFollowingAsync.value ?? false;
    final label =
        isFollowing ? 'Unfollow' : (item.actionLabel ?? 'Follow Back');

    return _FollowButton(
      label: label,
      onPressed: () async {
        final repo = ref.read(followRepoProvider);
        if (isFollowing) {
          await repo.unfollow(item.actorId);
        } else {
          await repo.follow(item.actorId);
        }
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

class _FollowRequestActions extends ConsumerStatefulWidget {
  const _FollowRequestActions({required this.item});
  final _Item item;

  @override
  ConsumerState<_FollowRequestActions> createState() =>
      _FollowRequestActionsState();
}

class _FollowRequestActionsState extends ConsumerState<_FollowRequestActions> {
  bool _busy = false;
  bool _resolved = false;

  Future<void> _markRead() async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    await ref
        .read(notificationsRepoProvider)
        .markRead(uid: me.uid, notificationId: widget.item.id);
  }

  Future<void> _accept() async {
    if (_busy || _resolved) return;
    setState(() {
      _busy = true;
      _resolved = true; // optimistic hide
    });
    try {
      await ref
          .read(followRepoProvider)
          .acceptRequest(
            senderId: widget.item.actorId,
            notificationId: widget.item.id,
          );
      await _markRead();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy || _resolved) return;
    setState(() {
      _busy = true;
      _resolved = true; // optimistic hide
    });
    try {
      await ref
          .read(followRepoProvider)
          .rejectRequest(
            senderId: widget.item.actorId,
            notificationId: widget.item.id,
          );
      await _markRead();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved) return const SizedBox.shrink();
    return Row(
      children: [
        TextButton(
          onPressed: _busy ? null : _reject,
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            backgroundColor: const Color(0xFFE3E3E3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.r),
            ),
          ),
          child: Text(
            'Reject',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 13.sp,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        TextButton(
          onPressed: _busy ? null : _accept,
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.r),
            ),
          ),
          child:
              _busy
                  ? SizedBox(
                    width: 14.r,
                    height: 14.r,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                  : Text(
                    'Accept',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                    ),
                  ),
        ),
      ],
    );
  }
}

Future<void> _handleTap(BuildContext context, WidgetRef ref, _Item item) async {
  switch (item.type) {
    case _ItemType.follow:
    case _ItemType.followRequest:
      await _openProfile(context, ref, item);
      break;
    case _ItemType.like:
    case _ItemType.comment:
    case _ItemType.reply:
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
          (_) => BoomerangPagerPage(
            initialId: data.$1,
            initialData: data.$2,
            targetCommentId: item.parentCommentId ?? item.commentId,
            targetReplyId: item.replyId,
          ),
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
