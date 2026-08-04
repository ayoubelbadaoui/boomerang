import 'package:boomerang/features/feed/infrastructure/boomerang_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedPost(
  FakeFirebaseFirestore fs, {
  required String id,
  required String userId,
  required DateTime createdAt,
  bool ownerIsPrivate = false,
}) async {
  await fs.collection('boomerangs').doc(id).set(<String, dynamic>{
    'userId': userId,
    'createdAt': Timestamp.fromDate(createdAt),
    'likes': 0,
    'commentsCount': 0,
    'ownerIsPrivate': ownerIsPrivate,
  });
}

Future<void> _seedUser(
  FakeFirebaseFirestore fs, {
  required String uid,
  bool isPrivate = false,
}) async {
  await fs.collection('users').doc(uid).set(<String, dynamic>{
    'nickname': uid,
    'isPrivate': isPrivate,
  });
}

void main() {
  late FakeFirebaseFirestore fs;
  late BoomerangRepo repo;
  final now = DateTime(2026, 1, 1, 12);

  setUp(() {
    fs = FakeFirebaseFirestore();
    repo = BoomerangRepo(fs);
  });

  group('fetchFollowingByCreatedAtPage', () {
    test('merges own, public-followed, and private-followed posts', () async {
      await _seedUser(fs, uid: 'pub');
      await _seedUser(fs, uid: 'priv', isPrivate: true);
      await _seedPost(fs,
          id: 'mine',
          userId: 'me',
          createdAt: now.subtract(const Duration(hours: 3)));
      await _seedPost(fs,
          id: 'pub1',
          userId: 'pub',
          createdAt: now.subtract(const Duration(hours: 1)));
      await _seedPost(fs,
          id: 'priv1',
          userId: 'priv',
          createdAt: now.subtract(const Duration(hours: 2)),
          ownerIsPrivate: true);

      final docs = await repo.fetchFollowingByCreatedAtPage(
        followingIds: {'pub', 'priv'},
        myUid: 'me',
        limit: 20,
      );

      expect(
        docs.map((d) => d.id).toList(),
        <String>['pub1', 'priv1', 'mine'],
      );
    });

    test('skips private query for public-only follows and still works '
        'without user docs', () async {
      // No users docs seeded at all — authors default to public.
      await _seedPost(fs,
          id: 'pub1',
          userId: 'friend',
          createdAt: now.subtract(const Duration(hours: 1)));

      final docs = await repo.fetchFollowingByCreatedAtPage(
        followingIds: {'friend'},
        myUid: 'me',
        limit: 20,
      );
      expect(docs.map((d) => d.id).toList(), <String>['pub1']);
    });

    test('respects limit and sorts across sources by createdAt desc',
        () async {
      await _seedUser(fs, uid: 'a');
      await _seedUser(fs, uid: 'b');
      for (var i = 0; i < 5; i++) {
        await _seedPost(fs,
            id: 'a$i',
            userId: 'a',
            createdAt: now.subtract(Duration(minutes: i * 2)));
        await _seedPost(fs,
            id: 'b$i',
            userId: 'b',
            createdAt: now.subtract(Duration(minutes: i * 2 + 1)));
      }

      final docs = await repo.fetchFollowingByCreatedAtPage(
        followingIds: {'a', 'b'},
        myUid: 'me',
        limit: 4,
      );
      expect(docs.map((d) => d.id).toList(), <String>['a0', 'b0', 'a1', 'b1']);
    });

    test('millisecond cursor excludes posts at/after the cursor', () async {
      await _seedUser(fs, uid: 'friend');
      await _seedPost(fs, id: 'newer', userId: 'friend', createdAt: now);
      await _seedPost(fs,
          id: 'older',
          userId: 'friend',
          createdAt: now.subtract(const Duration(hours: 1)));

      final docs = await repo.fetchFollowingByCreatedAtPage(
        followingIds: {'friend'},
        myUid: 'me',
        startAfterMillis: now.millisecondsSinceEpoch,
        limit: 20,
      );
      expect(docs.map((d) => d.id).toList(), <String>['older']);
    });
  });

  group('fetchPrivateWithSplit', () {
    FirebaseException denied() =>
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

    test('returns chunk result when nothing is denied', () async {
      var fetches = 0;
      final out = await BoomerangRepo.fetchPrivateWithSplit<String>(
        authors: ['a', 'b', 'c'],
        fetchChunk: (authors) async {
          fetches++;
          return authors.map((a) => 'post-$a').toList();
        },
        recoverAuthor: (_) async => fail('must not recover'),
      );
      expect(out, ['post-a', 'post-b', 'post-c']);
      expect(fetches, 1);
    });

    test('isolates a single bad author via binary split and recovers it',
        () async {
      final recovered = <String>[];
      final out = await BoomerangRepo.fetchPrivateWithSplit<String>(
        authors: List.generate(10, (i) => 'u$i'),
        fetchChunk: (authors) async {
          if (authors.contains('u7')) throw denied();
          return authors.map((a) => 'post-$a').toList();
        },
        recoverAuthor: (author) async {
          recovered.add(author);
          return const <String>[];
        },
      );
      expect(recovered, ['u7']);
      // Every readable author's posts survive.
      expect(
        out.toSet(),
        List.generate(10, (i) => 'post-u$i').toSet()..remove('post-u7'),
      );
    });

    test('handles multiple bad authors', () async {
      final recovered = <String>[];
      final bad = {'u1', 'u8'};
      final out = await BoomerangRepo.fetchPrivateWithSplit<String>(
        authors: List.generate(10, (i) => 'u$i'),
        fetchChunk: (authors) async {
          if (authors.any(bad.contains)) throw denied();
          return authors.map((a) => 'post-$a').toList();
        },
        recoverAuthor: (author) async {
          recovered.add(author);
          return const <String>[];
        },
      );
      expect(recovered.toSet(), bad);
      expect(out.length, 8);
    });

    test('rethrows non-permission errors', () async {
      expect(
        () => BoomerangRepo.fetchPrivateWithSplit<String>(
          authors: ['a'],
          fetchChunk: (_) async =>
              throw FirebaseException(plugin: 'x', code: 'unavailable'),
          recoverAuthor: (_) async => const <String>[],
        ),
        throwsA(isA<FirebaseException>()),
      );
    });
  });
}
