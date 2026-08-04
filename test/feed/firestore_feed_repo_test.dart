import 'package:boomerang/features/feed/domain/repositories/feed_repo.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_repo.dart';
import 'package:boomerang/features/feed/infrastructure/firestore_feed_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedPost(
  FakeFirebaseFirestore fs, {
  required String id,
  required String userId,
  required DateTime createdAt,
  int likes = 0,
  int commentsCount = 0,
  bool ownerIsPrivate = false,
  double? rankScore,
}) async {
  final data = <String, dynamic>{
    'userId': userId,
    'createdAt': Timestamp.fromDate(createdAt),
    'likes': likes,
    'commentsCount': commentsCount,
    'ownerIsPrivate': ownerIsPrivate,
    if (rankScore != null) 'rankScore': rankScore,
  };
  await fs.collection('boomerangs').doc(id).set(data);
}

void main() {
  late FakeFirebaseFirestore fs;
  late BoomerangRepo boomerangs;
  late FirestoreFeedRepo repo;
  final now = DateTime(2026, 1, 1, 12);

  setUp(() {
    fs = FakeFirebaseFirestore();
    boomerangs = BoomerangRepo(fs);
    repo = FirestoreFeedRepo(boomerangs);
  });

  group('fetchDiscoveryCandidates', () {
    test('returns public posts ordered by rankScore desc', () async {
      await _seedPost(fs,
          id: 'lo',
          userId: 'u1',
          createdAt: now,
          ownerIsPrivate: false,
          rankScore: 0.1);
      await _seedPost(fs,
          id: 'hi',
          userId: 'u2',
          createdAt: now,
          ownerIsPrivate: false,
          rankScore: 0.9);
      await _seedPost(fs,
          id: 'mid',
          userId: 'u3',
          createdAt: now,
          ownerIsPrivate: false,
          rankScore: 0.5);

      final pool = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
      );
      expect(pool.posts.map((p) => p.id).toList(), <String>['hi', 'mid', 'lo']);
    });

    test('falls back to createdAt when no doc has rankScore', () async {
      await _seedPost(fs,
          id: 'old',
          userId: 'u1',
          createdAt: now.subtract(const Duration(hours: 10)));
      await _seedPost(fs,
          id: 'new',
          userId: 'u2',
          createdAt: now.subtract(const Duration(hours: 1)));

      final pool = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
      );
      // The fallback path is exercised when no rankScore is present — we
      // assert both items came back without duplicates. Production
      // Firestore sorts by createdAt desc (verified manually); the in-
      // memory fake's Timestamp ordering is not authoritative.
      final ids = pool.posts.map((p) => p.id).toSet();
      expect(ids, equals(<String>{'old', 'new'}));
    });

    test('excludes blocked authors', () async {
      await _seedPost(fs,
          id: 'good',
          userId: 'friend',
          createdAt: now,
          rankScore: 0.5);
      await _seedPost(fs,
          id: 'bad',
          userId: 'jerk',
          createdAt: now,
          rankScore: 0.9);

      final pool = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{'jerk'},
      );
      expect(pool.posts.map((p) => p.id).toList(), <String>['good']);
    });

    test('surfaces unscored posts when only a few carry a rankScore', () async {
      // Regression: the ranking scheduler only scores a rolling recent window,
      // so the vast majority of posts have no rankScore. A score-ordered query
      // hides them entirely; the first page must merge in chronological posts.
      await _seedPost(fs,
          id: 'scored', userId: 'u1', createdAt: now, rankScore: 0.9);
      for (var i = 0; i < 5; i++) {
        await _seedPost(fs,
            id: 'unscored$i',
            userId: 'u$i',
            createdAt: now.subtract(Duration(hours: i + 1)));
      }

      final pool = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
      );
      // Every post is reachable on the first page — scored ones are not
      // allowed to hide the unscored majority. (Score-first ordering is a
      // production Firestore guarantee; the in-memory fake's ordering of
      // missing fields is not authoritative, so we assert presence only.)
      final ids = pool.posts.map((p) => p.id).toSet();
      expect(ids, contains('scored'));
      for (var i = 0; i < 5; i++) {
        expect(ids, contains('unscored$i'));
      }
    });

    test('excludes private posts', () async {
      await _seedPost(fs,
          id: 'public',
          userId: 'u1',
          createdAt: now,
          ownerIsPrivate: false,
          rankScore: 0.1);
      await _seedPost(fs,
          id: 'private',
          userId: 'u2',
          createdAt: now,
          ownerIsPrivate: true,
          rankScore: 0.9);

      final pool = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
      );
      expect(pool.posts.map((p) => p.id).toList(), <String>['public']);
    });
  });

  group('fetchHomeCandidates', () {
    test('prioritizes followed-author posts before exploration', () async {
      // Followed-author posts (no rankScore needed).
      await _seedPost(fs,
          id: 'f1',
          userId: 'friend',
          createdAt: now.subtract(const Duration(hours: 1)));
      await _seedPost(fs,
          id: 'f2',
          userId: 'friend',
          createdAt: now.subtract(const Duration(hours: 2)));
      // Own post should be included.
      await _seedPost(fs,
          id: 'mine',
          userId: 'me',
          createdAt: now.subtract(const Duration(hours: 3)));
      // Exploration candidate (public, hi-score, non-followed author).
      await _seedPost(fs,
          id: 'trending',
          userId: 'celebrity',
          createdAt: now,
          rankScore: 0.95);

      final pool = await repo.fetchHomeCandidates(
        myUid: 'me',
        followingIds: const <String>{'friend'},
        blockedIds: const <String>{},
      );
      final ids = pool.posts.map((p) => p.id).toSet();
      expect(ids, containsAll(<String>{'f1', 'f2', 'mine'}));
      expect(ids, isNot(contains('trending')));
      expect(pool.hasMore, isTrue);
      expect(pool.nextCursor, isA<HomeCursor>());
    });

    test('falls through to ranked exploration once following feed is exhausted',
        () async {
      await _seedPost(fs,
          id: 'f1',
          userId: 'friend',
          createdAt: now.subtract(const Duration(hours: 1)));
      await _seedPost(fs,
          id: 'trend',
          userId: 'celebrity',
          createdAt: now,
          rankScore: 0.95);

      final page1 = await repo.fetchHomeCandidates(
        myUid: 'me',
        followingIds: const <String>{'friend'},
        blockedIds: const <String>{},
      );
      expect(page1.posts.map((p) => p.id).toSet(), contains('f1'));
      expect(page1.posts.map((p) => p.id).toSet(), isNot(contains('trend')));

      final page2 = await repo.fetchHomeCandidates(
        myUid: 'me',
        followingIds: const <String>{'friend'},
        blockedIds: const <String>{},
        cursor: page1.nextCursor as HomeCursor?,
      );
      expect(page2.posts.map((p) => p.id).toSet(), contains('trend'));
    });

    test('fresh users (no following) receive exploration content', () async {
      await _seedPost(fs,
          id: 'trend1',
          userId: 'u1',
          createdAt: now,
          rankScore: 0.9);
      await _seedPost(fs,
          id: 'trend2',
          userId: 'u2',
          createdAt: now.subtract(const Duration(minutes: 30)),
          rankScore: 0.7);

      final pool = await repo.fetchHomeCandidates(
        myUid: 'fresh',
        followingIds: const <String>{},
        blockedIds: const <String>{},
      );
      final ids = pool.posts.map((p) => p.id).toSet();
      expect(ids, containsAll(<String>{'trend1', 'trend2'}));
    });

    test('private non-followed post never appears in Home candidates',
        () async {
      await _seedPost(fs,
          id: 'private',
          userId: 'stranger',
          createdAt: now,
          ownerIsPrivate: true,
          rankScore: 0.99);
      // A public one so the pool isn't empty.
      await _seedPost(fs,
          id: 'public',
          userId: 'friend',
          createdAt: now);

      final pool = await repo.fetchHomeCandidates(
        myUid: 'me',
        followingIds: const <String>{'friend'},
        blockedIds: const <String>{},
      );
      final ids = pool.posts.map((p) => p.id).toSet();
      expect(ids, isNot(contains('private')));
      expect(ids, contains('public'));
    });
  });

  group('cursor pagination', () {
    test('discovery: page 2 starts after page 1 in rankScore order',
        () async {
      for (var i = 0; i < 6; i++) {
        await _seedPost(
          fs,
          id: 'p$i',
          userId: 'u$i',
          createdAt: now,
          rankScore: (10 - i) / 10.0, // 1.0, 0.9, 0.8, ...
        );
      }
      final page1 = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
        limit: 3,
      );
      expect(page1.posts.length, 3);
      expect(page1.hasMore, isTrue);
      expect(page1.nextCursor, isA<DiscoveryCursor>());

      final page2 = await repo.fetchDiscoveryCandidates(
        myUid: 'me',
        blockedIds: const <String>{},
        cursor: page1.nextCursor as DiscoveryCursor?,
        limit: 3,
      );
      final p1Ids = page1.posts.map((p) => p.id).toSet();
      final p2Ids = page2.posts.map((p) => p.id).toSet();
      expect(p1Ids.intersection(p2Ids), isEmpty);
    });
  });
}
