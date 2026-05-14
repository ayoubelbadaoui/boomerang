import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/features/feed/application/feed_controller.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/utils/image_precache.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/feed/presentation/hashtag_feed_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';
import 'package:boomerang/core/widgets/boomerang_grid_shimmers.dart';
import 'package:boomerang/core/widgets/boomerang_grid_thumbnail.dart';
import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'dart:async';

class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  static const String routeName = '/discover_tab';

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  int _tabIndex = 0;
  late final TabController _tabController;
  final _usersController = ScrollController();
  final _tagsController = ScrollController();
  final _bmgController = ScrollController();
  Timer? _searchDebounce;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted && _tabController.index != _tabIndex) {
        setState(() {
          _tabIndex = _tabController.index;
        });
      }
    });
    _search.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _usersController.dispose();
    _tagsController.dispose();
    _bmgController.dispose();
    _searchDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final textTheme = Theme.of(context).textTheme;
    // no-op here; children decide based on query
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(88.h),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
            child: Container(
              height: 48.h,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  const Icon(Icons.search, color: Colors.black45),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.black,
              indicatorWeight: 3,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black45,
              labelStyle: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: textTheme.titleLarge?.fontSize ?? 18.sp,
              ),
              tabs: const [
                Tab(text: 'Bmg.'),
                Tab(text: 'Users'),
                Tab(text: 'Hashtag'),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BmgGrid(query: query),
                _UsersSearchList(query: query),
                _TagsSearchList(query: query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// _TabChip no longer used (replaced by TabBar)

class _UsersSearchList extends ConsumerWidget {
  const _UsersSearchList({required this.query});
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim();
    if (q.isEmpty) {
      return const Center(child: Text('Search users by name or @handle'));
    }
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    return FutureBuilder(
      future: ref
          .read(userSearchRepoProvider)
          .searchUsers(q.startsWith('@') ? q.substring(1) : q),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const DiscoverUsersListShimmer();
        }
        final allDocs = snapshot.data!;
        final docs = allDocs.where((d) {
          if (blockedSet.contains(d.id)) return false;
          return true;
        }).toList();
        if (docs.isEmpty) return const Center(child: Text('No users found'));
        return ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          itemCount: docs.length,
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final uid = docs[i].id;
            final name = (d['fullName'] ?? '') as String;
            final nick = (d['nickname'] ?? '') as String;
            final avatar = d['avatarUrl'] as String?;
            final handle = '@${nick.replaceAll(' ', '_').toLowerCase()}';
            return ListTile(
              leading: AppAvatar(url: avatar),
              title: Text(nick.isNotEmpty ? nick : name),
              subtitle: Text(handle),
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  builder:
                      (_) => ProfilePreviewSheet(
                        userId: uid,
                        handle: handle,
                      ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BmgGrid extends ConsumerWidget {
  const _BmgGrid({required this.query});
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = query.trim();
    final hasQuery = trimmed.isNotEmpty;
    final substring =
        hasQuery
            ? (trimmed.startsWith('#')
                ? trimmed.substring(1).toLowerCase()
                : trimmed.toLowerCase())
            : '';
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final myUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final followingIds =
        ref.watch(followingIdsProvider).value ?? const <String>{};
    final repo = ref.watch(boomerangRepoProvider);

    if (!hasQuery) {
      return _RankedBmgGrid(blockedSet: blockedSet, myUid: myUid);
    }

    final hashtagStream = ref.watch(hashtagRepoProvider).watchTop();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: hashtagStream,
      builder: (context, hashtagSnap) {
        if (!hashtagSnap.hasData) {
          return const DiscoverExploreGridShimmer();
        }
        final matches = hashtagSnap.data!.docs
            .map((d) => d.id)
            .where((id) => id.contains(substring))
            .take(30)
            .toList();
        if (matches.isEmpty) {
          return const Center(child: Text('No posts for this search'));
        }
        return _BmgGridContent(
          stream: repo.watchByHashtagsAny(
            matches,
            currentUserId: myUid,
            followingIds: followingIds,
          ),
          blockedSet: blockedSet,
          myUid: myUid,
          followingIds: followingIds,
        );
      },
    );
  }
}

/// Ranked Discovery grid backed by [FeedController]. Same masonry visual
/// as [_BmgGridContent] but the data source is the ranked pipeline and
/// pagination is driven by the controller, not a Firestore stream.
class _RankedBmgGrid extends ConsumerStatefulWidget {
  const _RankedBmgGrid({required this.blockedSet, required this.myUid});
  final Set<String> blockedSet;
  final String? myUid;

  @override
  ConsumerState<_RankedBmgGrid> createState() => _RankedBmgGridState();
}

class _RankedBmgGridState extends ConsumerState<_RankedBmgGrid> {
  final _controller = ScrollController();
  static int _lastWarmedHash = 0;

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
    const threshold = 600.0;
    if (_controller.position.maxScrollExtent - _controller.position.pixels <=
        threshold) {
      ref
          .read(feedControllerProvider(FeedSurface.discovery).notifier)
          .fetchNext();
    }
  }

  Future<void> _refresh() async {
    await ref
        .read(feedControllerProvider(FeedSurface.discovery).notifier)
        .refresh();
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync =
        ref.watch(feedControllerProvider(FeedSurface.discovery));
    if (!feedAsync.hasValue) {
      return const DiscoverExploreGridShimmer();
    }
    final state = feedAsync.value!;
    final visible = state.items
        .where((p) => !widget.blockedSet.contains(p.authorId))
        .toList(growable: false);

    if (visible.isEmpty && !state.isLoading) {
      return const Center(child: Text('No posts to discover yet'));
    }

    final snapHash =
        visible.length.hashCode ^ (visible.isNotEmpty ? visible.first.id.hashCode : 0);
    if (snapHash != _lastWarmedHash) {
      _lastWarmedHash = snapHash;
      final toWarm = visible
          .take(12)
          .map((p) => p.raw['imageUrl'])
          .whereType<String>()
          .toList();
      if (toWarm.isNotEmpty) {
        // ignore: discarded_futures
        precacheImages(toWarm, context, concurrency: 4);
      }
    }

    return RefreshIndicator(
      color: Colors.black,
      onRefresh: _refresh,
      child: ShimmerScope(
        child: MasonryGridView.count(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          crossAxisCount: 2,
          mainAxisSpacing: 16.h,
          crossAxisSpacing: 16.w,
          itemCount: visible.length + (state.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= visible.length) {
              return const DiscoverExploreGridShimmer();
            }
            final post = visible[i];
            final d = post.raw;
            final name = (d['userName'] ?? '') as String;
            final poster = (d['imageUrl'] ?? '') as String;
            final avatar = d['userAvatar'] as String?;
            final aspectRatio = i.isEven ? 9 / 14 : 9 / 11;
            final tileWidth =
                (MediaQuery.of(context).size.width - (16.w * 3)) / 2;
            final cacheW =
                (tileWidth * MediaQuery.of(context).devicePixelRatio).round();
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BoomerangPagerPage(
                      initialId: post.id,
                      initialData: d,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: aspectRatio,
                    child: BoomerangGridThumbnail(
                      imageUrl: poster.isNotEmpty ? poster : null,
                      borderRadius: BorderRadius.circular(18.r),
                      cacheWidth: cacheW,
                      phaseShift: i * 0.025,
                      usePlainNetwork: false,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      LiveAvatar(
                        userId: post.authorId,
                        fallbackUrl: avatar,
                        size: 24.r,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OtherUserProfilePage(
                                  userId: post.authorId,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Builds the actual masonry grid given a stream of post documents.
class _BmgGridContent extends ConsumerWidget {
  const _BmgGridContent({
    required this.stream,
    required this.blockedSet,
    required this.myUid,
    this.followingIds = const <String>{},
  });
  final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> stream;
  final Set<String> blockedSet;
  final String? myUid;
  final Set<String> followingIds;
  static int _lastWarmedHash = 0;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const DiscoverExploreGridShimmer();
        }
        final allDocs = snapshot.data!;
        final docs = allDocs.where((d) {
          final data = d.data();
          final uid = (data['userId'] ?? '') as String;
          if (blockedSet.contains(uid)) return false;
          if (uid == myUid) return true;
          // Posts from accounts the current user follows are visible
          // even when the owner is private (security rules already
          // verify the follow edge server-side).
          if (followingIds.contains(uid)) return true;
          if (data['ownerIsPrivate'] == true) return false;
          // Defensive check against stale denormalised flags: even when a
          // boomerang doc says public, look up the owner's live profile and
          // hide it if the account is private and we don't follow them.
          final liveProfile = ref.watch(userProfileByIdProvider(uid)).value;
          if (liveProfile != null && liveProfile.isPrivate) return false;
          return true;
        }).toList();
        // Warm-cache first page posters once per snapshot.
        final snapHash = docs.length.hashCode ^ (docs.isNotEmpty ? docs.first.id.hashCode : 0);
        if (snapHash != _lastWarmedHash) {
          _lastWarmedHash = snapHash;
          final toWarm = docs
              .take(12)
              .map((d) => d.data()['imageUrl'])
              .whereType<String>()
              .toList();
          if (toWarm.isNotEmpty) {
            // ignore: discarded_futures
            precacheImages(toWarm, context, concurrency: 4);
          }
        }
        return ShimmerScope(
          child: MasonryGridView.count(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            crossAxisCount: 2,
            mainAxisSpacing: 16.h,
            crossAxisSpacing: 16.w,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final name = (d['userName'] ?? '') as String;
              final poster = (d['imageUrl'] ?? '') as String;
              final avatar = (d['userAvatar'] as String?);
              final aspectRatio = i.isEven ? 9 / 14 : 9 / 11;
              final tileWidth =
                  (MediaQuery.of(context).size.width - (16.w * 3)) / 2;
              final cacheW =
                  (tileWidth * MediaQuery.of(context).devicePixelRatio).round();

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => BoomerangPagerPage(
                            initialId: id,
                            initialData: d,
                          ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: aspectRatio,
                      child: BoomerangGridThumbnail(
                        imageUrl: poster.isNotEmpty ? poster : null,
                        borderRadius: BorderRadius.circular(18.r),
                        cacheWidth: cacheW,
                        phaseShift: i * 0.025,
                        usePlainNetwork: false,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        LiveAvatar(
                          userId: (d['userId'] ?? '') as String,
                          fallbackUrl: avatar,
                          size: 24.r,
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (_) => OtherUserProfilePage(
                                        userId: (d['userId'] ?? '') as String,
                                      ),
                                ),
                              );
                            },
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TagsSearchList extends ConsumerWidget {
  const _TagsSearchList({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedQuery = query.startsWith('#')
        ? query.substring(1).trim()
        : query.trim();
    final needle = normalizedQuery.toLowerCase();

    if (normalizedQuery.isEmpty) {
      return const Center(child: Text('Search hashtags by typing #tag'));
    }

    final stream = ref.watch(hashtagRepoProvider).watchTop();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const DiscoverHashtagListShimmer();
        }
        // Client-side substring filter + simple relevance ranking:
        // exact match first, then prefix matches, then any-position
        // contains. Within each bucket the original order from the
        // server (count desc) is preserved.
        final exact = <String>[];
        final prefixed = <String>[];
        final contains = <String>[];
        for (final doc in snap.data!.docs) {
          final id = doc.id;
          if (id == needle) {
            exact.add(id);
          } else if (id.startsWith(needle)) {
            prefixed.add(id);
          } else if (id.contains(needle)) {
            contains.add(id);
          }
        }
        final results = [...exact, ...prefixed, ...contains];

        if (results.isEmpty) {
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            children: [
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text('#$needle'),
                subtitle: const Text('Search posts with this hashtag'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HashtagFeedPage(tag: needle),
                    ),
                  );
                },
              ),
              SizedBox(height: 16.h),
              const Center(child: Text('No hashtags found')),
            ],
          );
        }

        return ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          itemCount: results.length,
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, i) {
            final t = results[i];
            return ListTile(
              leading: const Icon(Icons.tag),
              title: Text(
                '#$t',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: t)),
                );
              },
            );
          },
        );
      },
    );
  }
}
