import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum FollowMode { following, followers }

class FollowListSheet extends ConsumerWidget {
  const FollowListSheet({super.key, required this.mode, required this.userId});
  final FollowMode mode;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = userId;
    final stream =
        mode == FollowMode.following
            ? ref.watch(followRepoProvider).watchFollowing(uid)
            : ref.watch(followRepoProvider).watchFollowers(uid);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              mode == FollowMode.following ? 'Following' : 'Followers',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12.h),
            const Divider(),
            SizedBox(height: 12.h),
            Expanded(
              child: StreamBuilder(
                stream: stream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        mode == FollowMode.following
                            ? 'No following yet'
                            : 'No followers yet',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 14.sp,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final name = (d['userName'] ?? 'User') as String;
                      final avatarFallback = d['userAvatar'] as String?;
                      final handle =
                          '@${name.replaceAll(' ', '_').toLowerCase()}';
                      final userId = (d['userId'] ?? '') as String;
                      return _FollowListTile(
                        name: name,
                        handle: handle,
                        avatarFallback: avatarFallback,
                        userId: userId,
                        // Only the followers list can render an action button.
                        // For the "following" list we keep a plain chevron.
                        showAction: mode == FollowMode.followers,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowListTile extends ConsumerStatefulWidget {
  const _FollowListTile({
    required this.name,
    required this.handle,
    required this.avatarFallback,
    required this.userId,
    required this.showAction,
  });

  final String name;
  final String handle;
  final String? avatarFallback;
  final String userId;
  final bool showAction;

  @override
  ConsumerState<_FollowListTile> createState() => _FollowListTileState();
}

class _FollowListTileState extends ConsumerState<_FollowListTile> {
  bool _loading = false;

  /// Short-lived optimistic flag bridging write latency. Cleared the moment
  /// the authoritative Firestore stream contradicts it (rejected / accepted /
  /// canceled), so the tile can never get stuck on "Pending".
  bool _optimisticRequested = false;

  Future<void> _toggle({
    required bool iFollow,
    required bool requested,
  }) async {
    if (_loading || widget.userId.isEmpty) return;
    setState(() => _loading = true);
    final repo = ref.read(followRepoProvider);
    try {
      if (iFollow) {
        await repo.unfollow(widget.userId);
        if (mounted) _optimisticRequested = false;
      } else if (requested) {
        await repo.cancelRequest(widget.userId);
        if (mounted) _optimisticRequested = false;
      } else {
        final outcome = await repo.followOrRequest(widget.userId);
        if (mounted) {
          _optimisticRequested = outcome == FollowOutcome.requested;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(currentUserProfileProvider).value?.uid;
    final isSelf = widget.userId.isNotEmpty && widget.userId == myUid;
    final hasValidTarget = widget.userId.isNotEmpty && !isSelf;

    // Keep the optimistic flag honest with respect to the real request doc
    // and the real edge doc. These listens run outside build so calling
    // setState inside them is safe.
    if (hasValidTarget) {
      ref.listen<AsyncValue<FollowRequest?>>(
        outgoingFollowRequestProvider(widget.userId),
        (prev, next) {
          final req = next.valueOrNull;
          // Request was rejected, canceled, or cleaned up: drop optimistic.
          if (_optimisticRequested && (req == null || !req.isPending)) {
            if (mounted) setState(() => _optimisticRequested = false);
          }
        },
      );
      ref.listen<AsyncValue<bool>>(
        isFollowingStreamProvider(widget.userId),
        (prev, next) {
          if ((next.valueOrNull ?? false) && _optimisticRequested) {
            if (mounted) setState(() => _optimisticRequested = false);
          }
        },
      );
    }

    final iFollow = hasValidTarget
        ? (ref.watch(isFollowingStreamProvider(widget.userId)).value ?? false)
        : false;
    final theyFollowMe = hasValidTarget
        ? (ref.watch(isFollowedByProvider(widget.userId)).value ?? false)
        : false;
    final outgoing = hasValidTarget
        ? ref.watch(outgoingFollowRequestProvider(widget.userId)).value
        : null;
    final requested =
        _optimisticRequested || (outgoing?.isPending == true);

    // The action button is only meaningful when we actually have something
    // useful to render: a live relationship (following/pending) OR the
    // user genuinely follows me (so "Follow back" is truthful).
    final renderAction = widget.showAction &&
        hasValidTarget &&
        (iFollow || requested || theyFollowMe);

    String label;
    if (iFollow) {
      label = 'Following';
    } else if (requested) {
      label = 'Pending';
    } else {
      label = 'Follow back';
    }

    final filled = !iFollow && !requested; // filled for primary CTA
    final bgColor = filled ? Colors.black : Colors.white;
    final fgColor = filled ? Colors.white : Colors.black;
    final borderColor = filled ? Colors.black : Colors.black26;

    return ListTile(
      onTap: () => _showProfilePreview(context, widget.handle, widget.userId),
      leading: SizedBox(
        width: 44.r,
        height: 44.r,
        child: LiveAvatar(
          userId: widget.userId,
          fallbackUrl: widget.avatarFallback,
          size: 44.r,
        ),
      ),
      title: Text(
        widget.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        widget.handle,
        style: const TextStyle(color: Colors.black54),
      ),
      trailing: renderAction
          ? SizedBox(
              height: 32.h,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : () => _toggle(iFollow: iFollow, requested: requested),
                style: ElevatedButton.styleFrom(
                  backgroundColor: bgColor,
                  foregroundColor: fgColor,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  shape: StadiumBorder(
                    side: BorderSide(color: borderColor, width: 1),
                  ),
                  textStyle: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 14.w,
                        height: 14.w,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fgColor,
                        ),
                      )
                    : Text(label),
              ),
            )
          : const Icon(Icons.chevron_right),
    );
  }
}

void _showProfilePreview(BuildContext context, String handle, String userId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => ProfilePreviewSheet(userId: userId, handle: handle),
  );
}
