import 'package:boomerang/core/widgets/avatar.dart';
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
    return FutureBuilder(
      future: ref
          .read(userSearchRepoProvider)
          .searchUsers(q.startsWith('@') ? q.substring(1) : q),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!;
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
                        avatarUrl: avatar,
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
  static int _lastWarmedHash = 0;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = query.trim();
    final isHashtag = trimmed.isNotEmpty;
    final tag =
        isHashtag
            ? (trimmed.startsWith('#')
                ? trimmed.substring(1).toLowerCase()
                : trimmed.toLowerCase())
            : '';
    final stream =
        isHashtag
            ? ref.watch(boomerangRepoProvider).watchByHashtag(tag)
            : ref.watch(boomerangRepoProvider).watchBoomerangs();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
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
          return MasonryGridView.count(
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
                    builder: (_) => BoomerangPagerPage(
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18.r),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (poster.isNotEmpty)
                            Image(
                              image: ResizeImage.resizeIfNeeded(
                                cacheW,
                                null,
                                NetworkImage(poster),
                              ),
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => Container(
                                    color: const Color(0xFFF2F2F2),
                                  ),
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFFEDEDED), Color(0xFFF7F7F7)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.black38,
                                  size: 36,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                Row(
                  children: [
                    AppAvatar(url: avatar, size: 24.r),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OtherUserProfilePage(
                                userId: (d['userId'] ?? '') as String,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TagsSearchList extends ConsumerStatefulWidget {
  const _TagsSearchList({required this.query});
  final String query;
  @override
  ConsumerState<_TagsSearchList> createState() => _TagsSearchListState();
}

class _TagsSearchListState extends ConsumerState<_TagsSearchList> {
  final _items = <String>[];
  DocumentSnapshot<Map<String, dynamic>>? _last;
  bool _loading = false;
  bool _hasMore = true;
  @override
  void didUpdateWidget(covariant _TagsSearchList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _items.clear();
      _last = null;
      _hasMore = true;
      _loading = false;
      setState(() {});
      _fetch();
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final q =
          widget.query.startsWith('#')
              ? widget.query.substring(1)
              : widget.query;
      final pref = q.trim().toLowerCase();
      if (pref.isEmpty) {
        setState(() {
          _items.clear();
          _loading = false;
          _hasMore = false;
        });
        return;
      }
      final snap = await ref
          .read(hashtagRepoProvider)
          .searchPrefixPage(prefix: pref, startAfter: _last, limit: 30);
      setState(() {
        _items.addAll(snap.docs.map((d) => d.id));
        if (snap.docs.isNotEmpty) _last = snap.docs.last;
        if (snap.docs.length < 30) _hasMore = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = widget.query.startsWith('#')
        ? widget.query.substring(1).trim()
        : widget.query.trim();
    final tag = normalizedQuery.toLowerCase();

    if (normalizedQuery.isEmpty) {
      return const Center(child: Text('Search hashtags by typing #tag'));
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        children: [
          ListTile(
            leading: const Icon(Icons.tag),
            title: Text('#$tag'),
            subtitle: const Text('Search posts with this hashtag'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag)),
              );
            },
          ),
          SizedBox(height: 16.h),
          const Center(child: Text('No hashtags found')),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !_loading &&
            _hasMore) {
          _fetch();
        }
        return false;
      },
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 8.h),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final t = _items[i];
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
      ),
    );
  }
}
