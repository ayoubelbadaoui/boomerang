import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/feed/presentation/hashtag_feed_page.dart';

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
  final _usersController = ScrollController();
  final _tagsController = ScrollController();
  final _bmgController = ScrollController();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _search.dispose();
    _usersController.dispose();
    _tagsController.dispose();
    _bmgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final isHashtag = query.startsWith('#') && query.length > 1;
    final tag = isHashtag ? query.substring(1).toLowerCase() : '';
    final stream =
        isHashtag
            ? ref.watch(boomerangRepoProvider).watchByHashtag(tag)
            : ref.watch(boomerangRepoProvider).watchBoomerangs();
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
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.tune_rounded),
                  ),
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
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                _TabChip(
                  label: 'Bmg.',
                  active: _tabIndex == 0,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                SizedBox(width: 24.w),
                _TabChip(
                  label: 'Users',
                  active: _tabIndex == 1,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
                SizedBox(width: 24.w),
                _TabChip(
                  label: 'Hashtag',
                  active: _tabIndex == 2,
                  onTap: () => setState(() => _tabIndex = 2),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 20.w, right: 20.w, top: 6.h),
            child: Container(height: 3, width: 60.w, color: Colors.black),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child:
                _tabIndex == 1
                    ? _UsersSearchList(query: query)
                    : _tabIndex == 2
                        ? _TagsSearchList(query: query)
                        : StreamBuilder(
                      stream: stream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final docs = snapshot.data!.docs;
                        return GridView.builder(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 8.h,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16.h,
                                crossAxisSpacing: 16.w,
                                childAspectRatio: 3 / 4,
                              ),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final d = docs[i].data();
                            final name = (d['userName'] ?? '') as String;
                            final poster = (d['imageUrl'] ?? '') as String;
                            final views =
                                (d['likes'] ?? 0) as int; // proxy as views
                            final avatar = (d['userAvatar'] as String?);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18.r),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          poster,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, __, ___) => Container(
                                                color: Colors.black12,
                                              ),
                                        ),
                                        Positioned(
                                          left: 8.w,
                                          bottom: 8.h,
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8.w,
                                              vertical: 4.h,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.6,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12.r),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.play_circle_filled,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                SizedBox(width: 4.w),
                                                Text(
                                                  '${(views / 1000).toStringAsFixed(1)}K',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
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
                                    CircleAvatar(
                                      radius: 12.r,
                                      backgroundImage:
                                          avatar != null
                                              ? NetworkImage(avatar)
                                              : null,
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.sp,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18.sp,
          color: active ? Colors.black : Colors.black45,
        ),
      ),
    );
  }
}

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
              leading: CircleAvatar(
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              ),
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
                        subtitle: '',
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
      final q = widget.query.startsWith('#')
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
      final snap = await ref.read(hashtagRepoProvider).searchPrefixPage(
            prefix: pref,
            startAfter: _last,
            limit: 30,
          );
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
    if (widget.query.trim().isEmpty) {
      return const Center(child: Text('Search hashtags by typing #tag'));
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No hashtags found'));
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
            title: Text('#$t', style: const TextStyle(fontWeight: FontWeight.w700)),
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
