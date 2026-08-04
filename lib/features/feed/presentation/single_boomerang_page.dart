import 'package:boomerang/core/utils/immersive_system_ui.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:boomerang/features/feed/presentation/widgets/fullscreen_boomerang_media.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/core/video/boomerang_video_cache.dart';
import 'package:video_player/video_player.dart';

class SingleBoomerangPage extends ConsumerStatefulWidget {
  const SingleBoomerangPage({super.key, required this.boomerangId});

  final String boomerangId;

  @override
  ConsumerState<SingleBoomerangPage> createState() =>
      _SingleBoomerangPageState();
}

class _SingleBoomerangPageState extends ConsumerState<SingleBoomerangPage> {
  Map<String, dynamic>? _data;
  String? _ownerId;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoController;
  bool _videoInitStarted = false;
  bool? _likedOverride;
  int? _likesOverride;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    ImmersiveSystemUi.enter();
    _loadPost();
  }

  Future<void> _loadPost() async {
    try {
      final repo = ref.read(boomerangRepoProvider);
      final result = await repo.fetchBoomerangById(widget.boomerangId);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'This boomerang is no longer available.';
        });
        return;
      }
      final (_, data) = result;
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      final likedBy =
          (data['likedBy'] as List?)?.whereType<String>().toSet() ?? <String>{};
      final seededUi = resolveActivePostLikeUiState(
        ref.read(postLikeUiEntryProvider(widget.boomerangId)),
      );
      final seededLiked =
          seededUi?.liked ?? (uid != null && likedBy.contains(uid));
      final serverLikes = ((data['likes'] ?? 0) as num).toInt();
      final seededLikes =
          seededUi?.likes ?? (serverLikes < 0 ? 0 : serverLikes);
      setState(() {
        _data = data;
        _ownerId = (data['userId'] ?? '') as String;
        _likedOverride = seededLiked;
        _likesOverride = seededLikes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load post.';
      });
    }
  }

  void _maybeStartVideo(String? url) {
    if (_videoInitStarted) return;
    if (url == null || url.isEmpty) return;
    _videoInitStarted = true;
    // ignore: discarded_futures
    BoomerangVideoCache.instance.createController(url).then((controller) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      _videoController = controller;
      controller
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            controller.setLooping(true);
            controller.play();
          }
        })
        ..setVolume(0);
    });
  }

  void _closePage() {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    Navigator.of(context).pop();
  }

  void _onToggleLike(bool liked, int likes) {
    final safeLikes = likes < 0 ? 0 : likes;
    if (!mounted) return;
    setState(() {
      _likedOverride = liked;
      _likesOverride = safeLikes;
    });
  }

  @override
  void dispose() {
    ImmersiveSystemUi.leave();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return _buildMessage(_error!);
    }

    final data = _data!;
    final ownerId = _ownerId ?? '';

    // Privacy gate: a private post must only be viewable by the owner or by
    // someone the owner has accepted as a follower. We rely on the live
    // owner profile, never the cached `ownerIsPrivate` flag, to avoid
    // serving stale data after a privacy toggle.
    final me = ref.watch(currentUserProfileProvider).value;
    final ownerProfile =
        ownerId.isEmpty
            ? null
            : ref.watch(userProfileByIdProvider(ownerId)).value;
    final cachedFlag = data['ownerIsPrivate'] == true;
    final ownerIsPrivate =
        (ownerProfile?.isPrivate ?? cachedFlag) || cachedFlag;
    final isOwner = me != null && me.uid == ownerId;
    final iFollow =
        ownerId.isEmpty
            ? false
            : (ref.watch(isFollowingStreamProvider(ownerId)).value ?? false);

    if (ownerIsPrivate && !isOwner && !iFollow) {
      return _buildPrivateNotice();
    }

    _maybeStartVideo(data['videoUrl'] as String?);

    final imageUrl = data['imageUrl'] as String?;
    final metadataAspect = _readAspect(data);

    return Stack(
      fit: StackFit.expand,
      children: [
        FullscreenBoomerangMedia(
          controller: _videoController,
          posterUrl: imageUrl,
          showPosterOverlay:
              _videoController == null || !_videoController!.value.isInitialized,
          explicitVideoAspectRatio: metadataAspect,
        ),
        BoomerangOverlay(
          boomerangId: widget.boomerangId,
          data: data,
          onBackPressed: () => _closePage(),
          likedOverride: _likedOverride,
          likesOverride: _likesOverride,
          onToggleLike: _onToggleLike,
        ),
      ],
    );
  }

  double? _readAspect(Map<String, dynamic> data) {
    final value = data['videoAspectRatio'];
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed.isFinite && parsed > 0) return parsed;
    }
    return null;
  }

  Widget _buildPrivateNotice() {
    return Stack(
      children: [
        const ColoredBox(color: Colors.black),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, color: Colors.white70, size: 56.sp),
                SizedBox(height: 16.h),
                Text(
                  'This post is from a private account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8.h),
                Text(
                  'Follow this account to see their boomerangs.',
                  style: TextStyle(color: Colors.white70, fontSize: 14.sp),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.h),
                TextButton(
                  onPressed: () => _closePage(),
                  child: const Text(
                    'Go back',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8.w,
          top: MediaQuery.viewPaddingOf(context).top + 8.h,
          child: IconButton(
            onPressed: () => _closePage(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String text) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 56.sp),
            SizedBox(height: 16.h),
            Text(
              text,
              style: TextStyle(color: Colors.white70, fontSize: 16.sp),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            TextButton(
              onPressed: () => _closePage(),
              child: const Text(
                'Go back',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
