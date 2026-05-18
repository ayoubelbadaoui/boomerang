import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' show log;
import 'dart:async';

class UserBoomerangsState {
  const UserBoomerangsState({
    required this.docs,
    required this.isLoading,
    required this.hasMore,
    required this.last,
  });
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool isLoading;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? last;

  UserBoomerangsState copyWith({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    bool? isLoading,
    bool? hasMore,
    DocumentSnapshot<Map<String, dynamic>>? last,
  }) {
    return UserBoomerangsState(
      docs: docs ?? this.docs,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      last: last ?? this.last,
    );
  }

  static const initial = UserBoomerangsState(
    docs: [],
    isLoading: false,
    hasMore: true,
    last: null,
  );
}

final userBoomerangsControllerProvider =
    AsyncNotifierProvider<UserBoomerangsController, UserBoomerangsState>(
      UserBoomerangsController.new,
    );

class UserBoomerangsController extends AsyncNotifier<UserBoomerangsState> {
  static const int _pageSize = 20;
  String? _activeUid;

  @override
  Future<UserBoomerangsState> build() async {
    _activeUid = ref.read(currentUserProfileProvider).value?.uid;
    ref.listen<AsyncValue<UserProfile?>>(currentUserProfileProvider, (
      previous,
      next,
    ) {
      final nextUid = next.asData?.value?.uid;
      if (nextUid == _activeUid) return;
      _activeUid = nextUid;
      state = const AsyncData(UserBoomerangsState.initial);
      if (nextUid != null && nextUid.isNotEmpty) {
        unawaited(fetchNext());
      }
    });

    // Start with an empty state; UI can trigger fetchNext or we can prefetch here.
    return UserBoomerangsState.initial;
  }

  Future<void> refresh() async {
    // Reset to initial and fetch the first page
    state = const AsyncData(UserBoomerangsState.initial);
    await fetchNext();
  }

  Future<void> deleteBoomerang(String boomerangId) async {
    final me = await ref.read(currentUserProfileProvider.future);
    if (me == null) return;

    await ref
        .read(boomerangRepoProvider)
        .deleteBoomerang(boomerangId: boomerangId, userId: me.uid);

    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          docs: current.docs.where((d) => d.id != boomerangId).toList(),
        ),
      );
    }
  }

  Future<void> fetchNext() async {
    final currentState = state.value ?? UserBoomerangsState.initial;
    if (currentState.isLoading || !currentState.hasMore) return;

    // Resolve current user
    final me = await ref.read(currentUserProfileProvider.future);
    if (me == null) return;
    final requestUid = me.uid;

    // Mark loading
    state = AsyncData(currentState.copyWith(isLoading: true));
    try {
      final repo = ref.read(boomerangRepoProvider);
      final snap = await repo.fetchUserBoomerangsPage(
        userId: me.uid,
        startAfter: currentState.last,
        limit: _pageSize,
      );
      final nextDocs = [...currentState.docs, ...snap.docs];
      final nextLast =
          snap.docs.isNotEmpty ? snap.docs.last : currentState.last;
      final nextHasMore = snap.docs.length >= _pageSize;
      final liveUid = ref.read(currentUserProfileProvider).value?.uid;
      if (liveUid != requestUid) {
        // Drop late result from previous account session.
        state = AsyncData(currentState.copyWith(isLoading: false));
        return;
      }
      state = AsyncData(
        currentState.copyWith(
          docs: nextDocs,
          last: nextLast,
          hasMore: nextHasMore,
          isLoading: false,
        ),
      );
    } catch (e, st) {
      log(
        'Failed to fetch user boomerangs page',
        name: 'UserBoomerangsController',
        error: e,
        stackTrace: st,
      );
      state = AsyncError(e, st);
    }
  }
}
