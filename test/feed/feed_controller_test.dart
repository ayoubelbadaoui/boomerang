import 'package:boomerang/features/feed/application/feed_controller.dart';
import 'package:boomerang/features/feed/application/feed_providers.dart';
import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/feed/domain/repositories/feed_repo.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFeedRepo implements FeedRepo {
  _FakeFeedRepo({required this.onHomeFetch});

  final CandidatePool Function(
    String myUid,
    Set<String> followingIds,
    Set<String> blockedIds,
    HomeCursor? cursor,
  )
  onHomeFetch;

  @override
  Future<CandidatePool> fetchHomeCandidates({
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    HomeCursor? cursor,
    int followingLimit = 60,
    int explorationLimit = 20,
  }) async {
    return onHomeFetch(myUid, followingIds, blockedIds, cursor);
  }

  @override
  Future<CandidatePool> fetchDiscoveryCandidates({
    required String myUid,
    required Set<String> blockedIds,
    DiscoveryCursor? cursor,
    int limit = 80,
  }) async {
    return const CandidatePool(
      posts: <RankedPost>[],
      nextCursor: null,
      hasMore: false,
    );
  }
}

RankedPost _post({
  required String id,
  required String authorId,
  required DateTime createdAt,
  int likes = 0,
  int comments = 0,
  double? rankScore,
}) {
  return RankedPost(
    id: id,
    authorId: authorId,
    createdAt: createdAt,
    likes: likes,
    commentsCount: comments,
    hashtags: const <String>[],
    ownerIsPrivate: false,
    serverRankScore: rankScore,
    raw: <String, dynamic>{
      'userId': authorId,
      'createdAt': createdAt,
      'likes': likes,
      'commentsCount': comments,
      'likedBy': const <String>[],
      'ownerIsPrivate': false,
      if (rankScore != null) 'rankScore': rankScore,
    },
  );
}

void main() {
  group('FeedController transition resilience', () {
    test(
      'does not deadlock when follow/block streams are transiently empty',
      () async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me'),
        );
        final repo = _FakeFeedRepo(
          onHomeFetch: (myUid, followingIds, blockedIds, cursor) {
            expect(myUid, 'me');
            expect(followingIds, isEmpty);
            expect(blockedIds, isEmpty);
            return CandidatePool(
              posts: <RankedPost>[
                _post(
                  id: 'p1',
                  authorId: 'author',
                  createdAt: DateTime(2026, 1, 1, 10),
                ),
              ],
              nextCursor: null,
              hasMore: false,
            );
          },
        );

        final container = ProviderContainer(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            feedRepoProvider.overrideWithValue(repo),
            followingIdsProvider.overrideWith(
              (_) => const Stream<Set<String>>.empty(),
            ),
            blockedUsersProvider.overrideWith(
              (_) => const Stream<List<String>>.empty(),
            ),
            feedDependencyMaxWaitProvider.overrideWithValue(
              const Duration(milliseconds: 20),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(feedControllerProvider(FeedSurface.home).future);
        await container
            .read(feedControllerProvider(FeedSurface.home).notifier)
            .fetchNext();

        final state =
            container.read(feedControllerProvider(FeedSurface.home)).value!;
        expect(state.isLoading, isFalse);
        expect(state.items.map((e) => e.id).toList(), <String>['p1']);
      },
    );

    test(
      'refresh pins newest posts to top window including my own newest',
      () async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me'),
        );
        final now = DateTime(2026, 1, 1, 12);
        final repo = _FakeFeedRepo(
          onHomeFetch: (myUid, followingIds, blockedIds, cursor) {
            return CandidatePool(
              posts: <RankedPost>[
                _post(
                  id: 'older-trending',
                  authorId: 'friend',
                  createdAt: now.subtract(const Duration(hours: 5)),
                  likes: 500,
                  comments: 150,
                  rankScore: 0.99,
                ),
                _post(
                  id: 'mine-newest',
                  authorId: 'me',
                  createdAt: now,
                  likes: 1,
                  comments: 0,
                  rankScore: 0.10,
                ),
                _post(
                  id: 'friend-mid',
                  authorId: 'friend',
                  createdAt: now.subtract(const Duration(hours: 2)),
                  likes: 30,
                  comments: 8,
                  rankScore: 0.7,
                ),
              ],
              nextCursor: null,
              hasMore: false,
            );
          },
        );

        final container = ProviderContainer(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            feedRepoProvider.overrideWithValue(repo),
            followingIdsProvider.overrideWith(
              (_) => Stream.value(<String>{'friend'}),
            ),
            blockedUsersProvider.overrideWith(
              (_) => Stream.value(const <String>[]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(feedControllerProvider(FeedSurface.home).future);
        await container
            .read(feedControllerProvider(FeedSurface.home).notifier)
            .refresh();

        final state =
            container.read(feedControllerProvider(FeedSurface.home)).value!;
        expect(state.items, isNotEmpty);
        expect(state.items.first.id, 'mine-newest');
      },
    );

    test(
      'ranking remains deterministic and page one order stays stable',
      () async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me'),
        );
        final now = DateTime(2026, 1, 1, 12);
        final repo = _FakeFeedRepo(
          onHomeFetch: (myUid, followingIds, blockedIds, cursor) {
            if (cursor == null) {
              return CandidatePool(
                posts: <RankedPost>[
                  _post(
                    id: 'p1',
                    authorId: 'friend',
                    createdAt: now.subtract(const Duration(hours: 1)),
                    rankScore: 0.8,
                    likes: 10,
                  ),
                  _post(
                    id: 'p2',
                    authorId: 'friend2',
                    createdAt: now.subtract(const Duration(hours: 2)),
                    rankScore: 0.7,
                    likes: 9,
                  ),
                ],
                nextCursor: const HomeCursor(
                  followingExhausted: true,
                  lastExplorationScore: 0.7,
                ),
                hasMore: true,
              );
            }
            return CandidatePool(
              posts: <RankedPost>[
                _post(
                  id: 'p3',
                  authorId: 'friend3',
                  createdAt: now.subtract(const Duration(hours: 3)),
                  rankScore: 0.6,
                  likes: 7,
                ),
                _post(
                  id: 'p4',
                  authorId: 'friend4',
                  createdAt: now.subtract(const Duration(hours: 4)),
                  rankScore: 0.5,
                  likes: 5,
                ),
              ],
              nextCursor: null,
              hasMore: false,
            );
          },
        );

        final container = ProviderContainer(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            feedRepoProvider.overrideWithValue(repo),
            followingIdsProvider.overrideWith(
              (_) => Stream.value(<String>{'friend'}),
            ),
            blockedUsersProvider.overrideWith(
              (_) => Stream.value(const <String>[]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(feedControllerProvider(FeedSurface.home).future);
        await container
            .read(feedControllerProvider(FeedSurface.home).notifier)
            .fetchNext();
        final firstPageOrder =
            container
                .read(feedControllerProvider(FeedSurface.home))
                .value!
                .items
                .map((e) => e.id)
                .toList();

        await container
            .read(feedControllerProvider(FeedSurface.home).notifier)
            .fetchNext();
        final mergedOrder =
            container
                .read(feedControllerProvider(FeedSurface.home))
                .value!
                .items
                .map((e) => e.id)
                .toList();

        expect(
          mergedOrder.take(firstPageOrder.length).toList(),
          firstPageOrder,
        );
        expect(mergedOrder.toSet().length, mergedOrder.length);
      },
    );
  });
}
