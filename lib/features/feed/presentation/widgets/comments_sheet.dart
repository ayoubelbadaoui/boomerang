import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    super.key,
    required this.boomerangId,
    required this.scrollController,
    this.targetCommentId,
    this.targetReplyId,
  });

  final String boomerangId;
  final ScrollController scrollController;
  final String? targetCommentId;
  final String? targetReplyId;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  String? _highlightCommentId;
  String? _highlightReplyId;
  final Map<String, GlobalKey> _commentKeys = {};
  final Map<String, GlobalKey> _replyKeys = {};

  @override
  void initState() {
    super.initState();
    _highlightCommentId = widget.targetCommentId;
    _highlightReplyId = widget.targetReplyId;
  }

  void _maybeScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.targetReplyId != null) {
        final key = _replyKeys[widget.targetReplyId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 400),
          );
          return;
        }
      }
      if (widget.targetCommentId != null) {
        final key = _commentKeys[widget.targetCommentId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 400),
          );
        }
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _highlightCommentId = null;
        _highlightReplyId = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(commentsRepoProvider).watch(widget.boomerangId);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          SizedBox(height: 8.h),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          StreamBuilder(
            stream: stream,
            builder: (context, snapshot) {
              final total = snapshot.data?.docs.length ?? 0;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Center(
                  child: Text(
                    total > 0 ? '$total Comments' : 'Comments',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No comments yet'));
                }
                _maybeScroll();
                return ListView.builder(
                  primary: false,
                  controller: widget.scrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final c = docs[i].data();
                    final commentId = docs[i].id;
                    final key = _commentKeys.putIfAbsent(
                      commentId,
                      () => GlobalKey(),
                    );
                    final isHighlight = _highlightCommentId == commentId;
                    return Container(
                      key: key,
                      color: isHighlight
                          ? Colors.yellow.withOpacity(0.15)
                          : Colors.transparent,
                      child: _CommentTile(
                        boomerangId: widget.boomerangId,
                        commentId: commentId,
                        userAvatar: c['userAvatar'] as String?,
                        userName: (c['userName'] ?? 'User') as String,
                        text: (c['text'] ?? '') as String,
                        likes: (c['likes'] ?? 0) as int,
                        likedBy:
                            (c['likedBy'] as List?)?.cast<String>() ??
                                const <String>[],
                        createdAt: (c['createdAt'] is Timestamp)
                            ? (c['createdAt'] as Timestamp).toDate()
                            : DateTime.now(),
                        highlightReplyId: _highlightReplyId,
                        replyKeys: _replyKeys,
                        targetReplyId: _highlightReplyId,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _CommentInput(boomerangId: widget.boomerangId),
        ],
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.boomerangId,
    required this.commentId,
    required this.userAvatar,
    required this.userName,
    required this.text,
    required this.likes,
    required this.likedBy,
    required this.createdAt,
    this.highlightReplyId,
    required this.replyKeys,
    this.targetReplyId,
  });
  final String boomerangId;
  final String commentId;
  final String? userAvatar;
  final String userName;
  final String text;
  final int likes;
  final List<String> likedBy;
  final DateTime createdAt;
  final String? highlightReplyId;
  final Map<String, GlobalKey> replyKeys;
  final String? targetReplyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final isLiked = me != null && likedBy.contains(me.uid);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(url: userAvatar, size: 56.r),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                        height: 1.4,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      text,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14.sp,
                        height: 1.4,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      children: [
                        InkWell(
                          onTap:
                              me == null
                                  ? null
                                  : () => ref
                                      .read(commentsRepoProvider)
                                      .toggleLike(
                                        boomerangId: boomerangId,
                                        commentId: commentId,
                                        userId: me.uid,
                                      ),
                          customBorder: const CircleBorder(),
                          child: Row(
                            children: [
                              Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                size: 22,
                                color: isLiked ? Colors.red : Colors.black54,
                              ),
                              SizedBox(width: 6.w),
                              Text(
                                '$likes',
                                style: TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Text(
                          _timeAgo(createdAt),
                          style: TextStyle(
                            color: Colors.black54,
                            fontFamily: 'Urbanist',
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(width: 16.w),
                        InkWell(
                          onTap: () => _openReply(context, ref),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_horiz, color: Colors.black54),
            ],
          ),
          _RepliesList(
            boomerangId: boomerangId,
            commentId: commentId,
            replyKeys: replyKeys,
            targetReplyId: highlightReplyId,
          ),
        ],
      ),
    );
  }

  void _openReply(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Add reply...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.r),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    final profileAsync = ref.read(currentUserProfileProvider);
                    final user = profileAsync.value;
                    controller.clear();
                    FocusScope.of(context).unfocus();
                    await ref
                        .read(commentsRepoProvider)
                        .addReply(
                          boomerangId: boomerangId,
                          parentCommentId: commentId,
                          userId: user?.uid ?? 'anon',
                          userName: user?.nickname.isNotEmpty == true
                              ? user!.nickname
                              : (user?.fullName ?? 'User'),
                          userAvatar: user?.avatarUrl,
                          text: text,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: CircleAvatar(
                    radius: 24.r,
                    backgroundColor: Colors.black,
                    child: const Icon(Icons.send, color: Colors.white),
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

class _RepliesList extends ConsumerWidget {
  const _RepliesList({
    required this.boomerangId,
    required this.commentId,
    required this.replyKeys,
    this.targetReplyId,
  });
  final String boomerangId;
  final String commentId;
  final Map<String, GlobalKey> replyKeys;
  final String? targetReplyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = FirebaseFirestore.instance
        .collection('boomerangs')
        .doc(boomerangId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .orderBy('createdAt', descending: true)
        .snapshots();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(left: 68.w, top: 8.h),
          child: Column(
            children: docs.map((d) {
              final r = d.data();
              final replyId = d.id;
              final avatar = r['userAvatar'] as String?;
              final name = (r['userName'] ?? 'User') as String;
              final text = (r['text'] ?? '') as String;
              final ts = r['createdAt'];
              final createdAt =
                  ts is Timestamp ? ts.toDate() : DateTime.now();
              final key = replyKeys.putIfAbsent(replyId, () => GlobalKey());
              final isHighlight = targetReplyId == replyId;
              return Padding(
                key: key,
                padding: EdgeInsets.only(bottom: 10.h),
                child: Container(
                  color: isHighlight
                      ? Colors.yellow.withOpacity(0.12)
                      : Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppAvatar(url: avatar, size: 40.r),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w700,
                                fontSize: 14.sp,
                                height: 1.4,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              text,
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 13.sp,
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              _timeAgo(createdAt),
                              style: TextStyle(
                                color: Colors.black45,
                                fontFamily: 'Urbanist',
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CommentInput extends ConsumerStatefulWidget {
  const _CommentInput({required this.boomerangId});
  final String boomerangId;

  @override
  ConsumerState<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<_CommentInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Add comment...',
                filled: true,
                fillColor: const Color(0xFFF6F6F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.r),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 14.h,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          InkWell(
            onTap: () async {
              final text = _controller.text.trim();
              if (text.isEmpty) return;
              final profileAsync = ref.read(currentUserProfileProvider);
              final user = profileAsync.value;
              _controller.clear();
              FocusScope.of(context).unfocus();
              await ref
                  .read(commentsRepoProvider)
                  .add(
                    boomerangId: widget.boomerangId,
                    userId: user?.uid ?? 'anon',
                    userName: user?.nickname.isNotEmpty == true
                        ? user!.nickname
                        : (user?.fullName ?? 'User'),
                    userAvatar: user?.avatarUrl,
                    text: text,
                  );
            },
            child: CircleAvatar(
              radius: 24.r,
              backgroundColor: Colors.black,
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
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
