import 'package:boomerang/features/feed/infrastructure/boomerang_repo.dart';
import 'package:boomerang/features/feed/presentation/single_boomerang_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBoomerangRepo extends BoomerangRepo {
  _FakeBoomerangRepo(this._payload) : super(FakeFirebaseFirestore());

  final Map<String, dynamic> _payload;

  @override
  Future<(String, Map<String, dynamic>)?> fetchBoomerangById(
    String boomerangId,
  ) async {
    return (boomerangId, Map<String, dynamic>.from(_payload));
  }
}

void main() {
  testWidgets('shows like count from shared UI state for message-opened post', (
    tester,
  ) async {
    final repo = _FakeBoomerangRepo(<String, dynamic>{
      'userId': 'owner-1',
      'userName': 'Owner',
      'likes': 5,
      'likedBy': <String>[],
      'ownerIsPrivate': false,
      'imageUrl': '',
      'videoUrl': '',
    });
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me-1'),
    );
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        boomerangRepoProvider.overrideWithValue(repo),
        firebaseAuthProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(postLikeUiControllerProvider.notifier)
        .setStateForPost(postId: 'post-1', liked: true, likes: 42);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => const MaterialApp(
                home: SingleBoomerangPage(boomerangId: 'post-1'),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('back closes page cleanly', (tester) async {
    final repo = _FakeBoomerangRepo(<String, dynamic>{
      'userId': 'owner-1',
      'userName': 'Owner',
      'likes': 3,
      'likedBy': <String>[],
      'ownerIsPrivate': false,
      'imageUrl': '',
      'videoUrl': '',
    });
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me-1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          boomerangRepoProvider.overrideWithValue(repo),
          firebaseAuthProvider.overrideWithValue(auth),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                home: Builder(
                  builder:
                      (context) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder:
                                      (_) => const SingleBoomerangPage(
                                        boomerangId: 'post-2',
                                      ),
                                ),
                              );
                            },
                            child: const Text('Open Post'),
                          ),
                        ),
                      ),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open Post'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleBoomerangPage), findsOneWidget);

    expect(find.byType(IconButton), findsWidgets);
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(SingleBoomerangPage), findsNothing);
  });
}
