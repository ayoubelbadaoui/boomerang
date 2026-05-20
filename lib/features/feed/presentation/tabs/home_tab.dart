import 'dart:async';
import 'package:boomerang/core/widgets/hashtag_caption.dart';
import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/features/feed/application/feed_controller.dart';
import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:boomerang/features/feed/presentation/navigation/user_profile_navigation.dart';
import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:boomerang/features/chat/presentation/widgets/send_post_sheet.dart';
import 'package:boomerang/core/widgets/boomerang_feed_post_shimmer.dart';
import 'package:boomerang/core/widgets/instagram_shimmer.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  static const String routeName = '/home_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PaginatedBoomerangList();
  }
}

class _PaginatedBoomerangList extends ConsumerStatefulWidget {
  const _PaginatedBoomerangList();
  @override
  ConsumerState<_PaginatedBoomerangList> createState() =>
      _PaginatedBoomerangListState();
}

class _PaginatedBoomerangListState
    extends ConsumerState<_PaginatedBoomerangList> {
  final _controller = ScrollController();
  final _localLiked = <String, bool>{};
  final _localLikeCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    const threshold = 300.0;
    if (_controller.position.maxScrollExtent - _controller.position.pixels <=
        threshold) {
      ref.read(feedControllerProvider(FeedSurface.home).notifier).fetchNext();
    }
  }

  Future<void> _refresh() async {
    await ref.read(feedControllerProvider(FeedSurface.home).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final followingAsync = ref.watch(followingIdsProvider);
    final feedAsync = ref.watch(feedControllerProvider(FeedSurface.home));

    final hasFollowing = followingAsync.hasValue;
    final hasFeedValue = feedAsync.hasValue;
    final feedState = feedAsync.value;

    // Render shimmer until both the follow set and the first page resolve.
    if (!hasFollowing || !hasFeedValue) {
      return ColoredBox(
        color: InstagramShimmerColors.lightCanvas,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 24.h),
                child: const BoomerangFeedPostShimmer(),
              ),
          ],
        ),
      );
    }

    final me = ref.watch(currentUserProfileProvider).value;
    final meUid = me?.uid ?? '';
    final currentFollowingIds = followingAsync.value ?? const <String>{};

    // Defense-in-depth: re-apply block + privacy filters in case the user
    // blocked someone mid-session. The repo already filters at fetch time.
    final visibleItems = feedState!.items
        .where((p) {
          if (blockedSet.contains(p.authorId)) return false;
          if (p.ownerIsPrivate &&
              !currentFollowingIds.contains(p.authorId) &&
              p.authorId != meUid) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    final hasMore = feedState.hasMore;
    final isLoading = feedState.isLoading;
    final isLoadingInitial = visibleItems.isEmpty && isLoading;

    return RefreshIndicator(
      color: Colors.black,
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        primary: false,
        controller: _controller,
        addAutomaticKeepAlives: false,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
        itemCount:
            isLoadingInitial
                ? 3
                : (visibleItems.length +
                    (hasMore ? 1 : (visibleItems.isEmpty ? 1 : 0))),
        separatorBuilder: (_, __) => const SizedBox(),
        itemBuilder: (context, i) {
          if (isLoadingInitial) {
            return Padding(
              padding: EdgeInsets.only(bottom: 24.h),
              child: const BoomerangFeedPostShimmer(),
            );
          }
          if (visibleItems.isEmpty) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 60.h),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48.r, color: Colors.black26),
                  SizedBox(height: 12.h),
                  Text(
                    'Follow people to see their boomerangs here',
                    style: TextStyle(fontSize: 15.sp, color: Colors.black45),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          if (i >= visibleItems.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: const BoomerangFeedPostShimmer(),
            );
          }
          final RankedPost post = visibleItems[i];
          final globalLike = resolveActivePostLikeUiState(
            ref.watch(postLikeUiEntryProvider(post.id)),
          );
          final overrideLiked = _localLiked[post.id];
          final likesOverride = _localLikeCounts[post.id];
          final likedBy =
              (post.raw['likedBy'] as List?)?.cast<String>() ??
              const <String>[];
          final isLiked =
              overrideLiked ?? globalLike?.liked ?? likedBy.contains(meUid);
          final rawLikes = (post.raw['likes'] ?? 0) as int;
          final effectiveLikes = likesOverride ?? globalLike?.likes ?? rawLikes;
          return _BoomerangCard(
            key: ValueKey(post.id),
            id: post.id,
            data: post.raw,
            likedOverride: isLiked,
            likesOverride: effectiveLikes,
            onToggleLike: (liked, likes) {
              final safeLikes = likes < 0 ? 0 : likes;
              setState(() {
                _localLiked[post.id] = liked;
                _localLikeCounts[post.id] = safeLikes;
              });
              ref
                  .read(postLikeUiControllerProvider.notifier)
                  .setStateForPost(
                    postId: post.id,
                    liked: liked,
                    likes: safeLikes,
                  );
            },
          );
        },
      ),
    );
  }
}

class _BoomerangCard extends ConsumerStatefulWidget {
  const _BoomerangCard({
    super.key,
    required this.id,
    required this.data,
    this.likedOverride,
    this.likesOverride,
    this.onToggleLike,
  });
  final String id;
  final Map<String, dynamic> data;
  final bool? likedOverride;
  final int? likesOverride;
  final void Function(bool liked, int likes)? onToggleLike;

  @override
  ConsumerState<_BoomerangCard> createState() => _BoomerangCardState();
}

class _BoomerangCardState extends ConsumerState<_BoomerangCard> {
  bool _mediaReady = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final id = widget.id;
    final userId = (data['userId'] ?? '') as String;
    final liveName = ref.watch(userDisplayNameByIdProvider(userId));
    final fallbackName = (data['userName'] ?? 'user').toString();
    final displayName =
        liveName?.trim().isNotEmpty == true ? liveName!.trim() : fallbackName;
    final handle = '@${displayName.replaceAll(' ', '_').toLowerCase()}';
    final avatarFallback = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?; // optional poster
    final video = data['videoUrl'] as String?;
    final likes = (widget.likesOverride ?? data['likes'] ?? 0) as int;
    final me = ref.read(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked =
        widget.likedOverride ?? (me != null && likedBy.contains(me.uid));
    debugPrint(
      'card build: $id isLiked=$isLiked source=${widget.likedOverride != null ? 'override' : 'firestore'} likes=$likes',
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24.r),
          child: Container(
            color:
                (image != null && image.isNotEmpty)
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF2F2F2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: _DoubleTapLikeArea(
                    postId: id,
                    data: data,
                    isLiked: isLiked,
                    currentLikes: likes,
                    onToggleLike: (liked, nextLikes) {
                      widget.onToggleLike?.call(
                        liked,
                        nextLikes < 0 ? 0 : nextLikes,
                      );
                    },
                    child: _BoomerangMedia(
                      videoUrl: video,
                      posterUrl: image,
                      postId: id,
                      onFullyReady: (ready) {
                        if (!mounted) return;
                        if (_mediaReady != ready) {
                          setState(() => _mediaReady = ready);
                        }
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 18.w,
                  top: 16.h,
                  child: Row(
                    children: [
                      InkWell(
                        onTap:
                            () => openUserProfilePreview(
                              context,
                              ref,
                              userId: userId,
                              handle: handle,
                            ),
                        customBorder: const CircleBorder(),
                        child: LiveAvatar(
                          userId: userId,
                          fallbackUrl: avatarFallback,
                          size: 36.r,
                        ),
                      ),
                      SizedBox(width: 10.w),
                      InkWell(
                        onTap:
                            () => openUserProfilePreview(
                              context,
                              ref,
                              userId: userId,
                              handle: handle,
                            ),
                        child: Text(
                          handle,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 20.w,
                  top: 18.h,
                  child: _BookmarkButton(postId: id, data: data),
                ),
                Positioned(
                  left: 12.w,
                  bottom: 20.h,
                  child: Row(
                    children: [
                      _CommentButton(boomerangId: id, data: data),
                      SizedBox(width: 8.w),
                      _SvgCircleBtn(
                        asset: 'assets/svgs/share.svg',
                        onTap:
                            () =>
                                _showShareSheet(context, data, boomerangId: id),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 18.w,
                  bottom: 24.h,
                  child: _LikeCircleButton(
                    isLiked: isLiked,
                    likes: likes,
                    onToggleLike: (nextLiked, nextLikes) async {
                      final uid =
                          ref.read(firebaseAuthProvider).currentUser?.uid;
                      if (uid == null) return;
                      final me = ref.read(currentUserProfileProvider).value;
                      final previousLiked = isLiked;
                      final previousLikes = likes < 0 ? 0 : likes;
                      final authUser =
                          ref.read(firebaseAuthProvider).currentUser;
                      try {
                        final result = await ref
                            .read(boomerangRepoProvider)
                            .setLike(
                              boomerangId: id,
                              userId: uid,
                              shouldLike: nextLiked,
                              actorName:
                                  me != null
                                      ? _bestName(me)
                                      : (authUser?.displayName ?? 'User'),
                              actorAvatar: me?.avatarUrl ?? authUser?.photoURL,
                            );
                        if (result != null) {
                          widget.onToggleLike?.call(result.liked, result.likes);
                        }
                      } catch (_) {
                        widget.onToggleLike?.call(previousLiked, previousLikes);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      handle,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    HashtagCaption(
                      caption: (data['caption'] ?? '') as String? ?? '',
                      maxLines: 2,
                      style: TextStyle(color: Colors.black87, fontSize: 14.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedOpacity(
          opacity: _mediaReady ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: IgnorePointer(ignoring: !_mediaReady, child: content),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _mediaReady,
            child: AnimatedOpacity(
              opacity: _mediaReady ? 0 : 1,
              duration: const Duration(milliseconds: 260),
              child: const BoomerangFeedPostShimmer(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SvgCircleBtn extends StatelessWidget {
  const _SvgCircleBtn({required this.asset, this.onTap});
  final String asset;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(12.r),
        child: SvgPicture.asset(
          asset,
          width: 24.r,
          height: 24.r,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _CommentButton extends ConsumerWidget {
  const _CommentButton({required this.boomerangId, required this.data});
  final String boomerangId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showCommentsSheet(context, boomerangId, data),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(12.r),
        child: SvgPicture.asset(
          'assets/svgs/comment.svg',
          width: 24.r,
          height: 24.r,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _BookmarkButton extends ConsumerWidget {
  const _BookmarkButton({required this.postId, required this.data});
  final String postId;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    if (me == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<bool>(
      stream: ref
          .watch(savedRepoProvider)
          .watchIsSaved(userId: me.uid, boomerangId: postId),
      initialData: false,
      builder: (context, snap) {
        final saved = snap.data ?? false;
        return InkWell(
          onTap: () async {
            await ref
                .read(savedRepoProvider)
                .toggleSave(
                  userId: me.uid,
                  boomerangId: postId,
                  boomerangData: data,
                );
          },
          customBorder: const CircleBorder(),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            padding: EdgeInsets.all(12.r),
            child: SvgPicture.asset(
              'assets/svgs/Bookmark.svg',
              width: 24.r,
              height: 24.r,
              colorFilter: ColorFilter.mode(
                saved ? Colors.yellow : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikeCircleButton extends ConsumerStatefulWidget {
  const _LikeCircleButton({
    required this.isLiked,
    required this.likes,
    required this.onToggleLike,
  });
  final bool isLiked;
  final int likes;
  final Future<void> Function(bool nextLiked, int nextLikes) onToggleLike;

  @override
  ConsumerState<_LikeCircleButton> createState() => _LikeCircleButtonState();
}

class _LikeCircleButtonState extends ConsumerState<_LikeCircleButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    final nextLiked = !widget.isLiked;
    final nextLikesRaw = widget.likes + (nextLiked ? 1 : -1);
    final nextLikes = nextLikesRaw < 0 ? 0 : nextLikesRaw;
    setState(() => _busy = true);
    try {
      await widget.onToggleLike(nextLiked, nextLikes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _tap,
      customBorder: const CircleBorder(),
      child: SvgPicture.asset(
        'assets/heart.svg',
        width: 36.w,
        height: 36.w,
        colorFilter: ColorFilter.mode(
          widget.isLiked ? Colors.red : Colors.white,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _DoubleTapLikeArea extends ConsumerStatefulWidget {
  const _DoubleTapLikeArea({
    required this.postId,
    required this.data,
    required this.child,
    required this.isLiked,
    required this.currentLikes,
    required this.onToggleLike,
  });
  final String postId;
  final Map<String, dynamic> data;
  final Widget child;
  final bool isLiked;
  final int currentLikes;
  final void Function(bool liked, int likes) onToggleLike;
  @override
  ConsumerState<_DoubleTapLikeArea> createState() => _DoubleTapLikeAreaState();
}

String _bestName(UserProfile profile) {
  if (profile.nickname.trim().isNotEmpty) return profile.nickname;
  if (profile.fullName.trim().isNotEmpty) return profile.fullName;
  return 'User';
}

class _DoubleTapLikeAreaState extends ConsumerState<_DoubleTapLikeArea>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  bool _busy = false;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    if (_busy || widget.isLiked) return;
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    setState(() => _busy = true);
    widget.onToggleLike(true, widget.currentLikes + 1);
    try {
      final result = await ref
          .read(boomerangRepoProvider)
          .setLike(
            boomerangId: widget.postId,
            userId: me.uid,
            shouldLike: true,
            actorName: _bestName(me),
            actorAvatar: me.avatarUrl,
          );
      if (result != null) {
        widget.onToggleLike(result.liked, result.likes);
      }
    } catch (_) {
      widget.onToggleLike(widget.isLiked, widget.currentLikes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDoubleTap() async {
    setState(() => _showHeart = true);
    _controller.forward(from: 0);
    await _like();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final seededData = Map<String, dynamic>.from(widget.data);
        final authUid = ref.read(firebaseAuthProvider).currentUser?.uid;
        seededData['likes'] = widget.currentLikes < 0 ? 0 : widget.currentLikes;
        if (authUid != null) {
          final likedBy =
              ((seededData['likedBy'] as List?) ?? const <dynamic>[])
                  .whereType<String>()
                  .toSet();
          if (widget.isLiked) {
            likedBy.add(authUid);
          } else {
            likedBy.remove(authUid);
          }
          seededData['likedBy'] = likedBy.toList(growable: false);
        }
        final result = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder:
                (_) => BoomerangPagerPage(
                  initialId: widget.postId,
                  initialData: seededData,
                ),
          ),
        );
        if (!mounted || result == null) return;
        final liked = result['liked'] == true;
        final likes = ((result['likes'] ?? widget.currentLikes) as num).toInt();
        widget.onToggleLike(liked, likes < 0 ? 0 : likes);
      },
      onDoubleTap: _onDoubleTap,
      onLongPress: null,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_showHeart)
            Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.2).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutBack,
                  ),
                ),
                child: Icon(
                  Icons.favorite,
                  color: Colors.white.fade(0.9),
                  size: 100.r,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showShareSheet(
  BuildContext context,
  Map<String, dynamic> data, {
  required String boomerangId,
}) {
  final videoUrl = data['videoUrl'] as String?;
  final shareText = videoUrl ?? 'Check out this Boomerang!';
  final userId = (data['userId'] ?? '') as String;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              _ShareOption(
                icon: Icons.send_rounded,
                label: 'Send',
                onTap: () {
                  Navigator.pop(context);
                  final imageUrl = (data['imageUrl'] ?? '') as String;
                  final userName = (data['userName'] ?? '') as String;
                  final caption = data['caption'] as String?;
                  showSendPostSheet(
                    context,
                    boomerangId: boomerangId,
                    imageUrl: imageUrl,
                    userName: userName,
                    caption: caption,
                  );
                },
              ),
              _ShareOption(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Navigator.pop(context);
                  // ignore: deprecated_member_use
                  Share.share(shareText);
                },
              ),
              _ShareOption(
                icon: Icons.link_rounded,
                label: 'Copy link',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
              ),
              _ShareOption(
                icon: Icons.download_outlined,
                label: 'Save',
                onTap: () async {
                  if (videoUrl != null && videoUrl.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: videoUrl));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Boomerang link copied')),
                      );
                    }
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
              _ShareOption(
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: () {
                  Navigator.pop(context);
                  showReportSheet(
                    context,
                    reportedUid: userId,
                    boomerangId: boomerangId,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showCommentsSheet(
  BuildContext context,
  String boomerangId,
  Map<String, dynamic> data,
) {
  final postOwnerId = (data['userId'] ?? '') as String;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.98,
        minChildSize: 0.5,
        builder:
            (context, controller) => CommentsSheet(
              boomerangId: boomerangId,
              scrollController: controller,
              postOwnerId: postOwnerId,
            ),
      );
    },
  );
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 44.r,
              height: 44.r,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F2F2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black, size: 22.r),
            ),
            SizedBox(width: 16.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoomerangMedia extends StatefulWidget {
  const _BoomerangMedia({
    required this.videoUrl,
    required this.posterUrl,
    required this.postId,
    this.onFullyReady,
  });
  final String? videoUrl;
  final String? posterUrl;
  final String postId;
  final ValueChanged<bool>? onFullyReady;

  @override
  State<_BoomerangMedia> createState() => _BoomerangMediaState();
}

class _BoomerangMediaState extends State<_BoomerangMedia> {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  bool _videoInitFailed = false;
  bool _visible = false;
  bool _initialized = false;
  bool _posterResolved = false;

  /// Once true, keep showing the card while video initializes (no shimmer flash).
  bool _mediaUnlocked = false;
  bool _lastEmittedReady = false;

  @override
  void initState() {
    super.initState();
    _posterResolved = widget.posterUrl == null || widget.posterUrl!.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitReadyIfChanged());
  }

  @override
  void didUpdateWidget(covariant _BoomerangMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl ||
        widget.posterUrl != oldWidget.posterUrl ||
        widget.postId != oldWidget.postId) {
      _mediaUnlocked = false;
      _lastEmittedReady = false;
    }
    if (widget.videoUrl != oldWidget.videoUrl) {
      _videoInitFailed = false;
      _disposeController();
      if (_visible) _initController();
      _emitReadyIfChanged();
    }
    if (widget.posterUrl != oldWidget.posterUrl) {
      _posterResolved = widget.posterUrl == null || widget.posterUrl!.isEmpty;
      _emitReadyIfChanged();
    }
  }

  bool _computeReady() {
    final hasVideo = widget.videoUrl != null && widget.videoUrl!.isNotEmpty;
    final hasPoster = widget.posterUrl != null && widget.posterUrl!.isNotEmpty;

    if (_videoInitFailed) {
      return !hasPoster || _posterResolved;
    }
    if (!hasVideo) {
      return !hasPoster || _posterResolved;
    }

    final posterOk = !hasPoster || _posterResolved;
    if (!posterOk) return false;

    if (!_visible) {
      _mediaUnlocked = true;
      return true;
    }
    if (_videoReady) {
      _mediaUnlocked = true;
      return true;
    }
    return _mediaUnlocked;
  }

  void _emitReadyIfChanged() {
    final ready = _computeReady();
    if (ready == _lastEmittedReady) return;
    _lastEmittedReady = ready;
    widget.onFullyReady?.call(ready);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final nowVisible = info.visibleFraction >= 0.5;
    if (nowVisible == _visible) return;
    _visible = nowVisible;

    if (_visible) {
      if (!_initialized) {
        _initController();
      } else {
        _controller?.play();
      }
    } else {
      _controller?.pause();
    }
    _emitReadyIfChanged();
  }

  Future<void> _initController() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;
    _videoReady = false;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      _initialized = true;
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      if (_visible) await controller.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      if (mounted) {
        setState(() => _videoInitFailed = true);
      }
    } finally {
      _emitReadyIfChanged();
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _videoReady = false;
    _initialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPoster = widget.posterUrl != null && widget.posterUrl!.isNotEmpty;

    Widget posterLayer() {
      if (hasPoster) {
        final cacheW =
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round();
        return Image.network(
          widget.posterUrl!,
          fit: BoxFit.cover,
          cacheWidth: cacheW,
          frameBuilder: (context, child, frame, wasSyncLoaded) {
            final done = frame != null || wasSyncLoaded;
            if (done && !_posterResolved) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _posterResolved = true);
                _emitReadyIfChanged();
              });
            }
            return child;
          },
          errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_posterResolved) {
                setState(() => _posterResolved = true);
                _emitReadyIfChanged();
              }
            });
            return const SizedBox.shrink();
          },
        );
      }
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEDEDED), Color(0xFFF7F7F7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.black38, size: 42),
        ),
      );
    }

    final hasVideo = _controller != null && _controller!.value.isInitialized;

    return VisibilityDetector(
      key: Key('bmg-media-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _videoReady ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 220),
            child: posterLayer(),
          ),
          if (hasVideo)
            AnimatedOpacity(
              opacity: _videoReady ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
