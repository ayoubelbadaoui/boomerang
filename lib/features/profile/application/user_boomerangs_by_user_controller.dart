import 'package:boomerang/infrastructure/providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  static const initial =
      UserBoomerangsState(docs: [], isLoading: false, hasMore: true, last: null);
}

final userBoomerangsByUserControllerProvider = AsyncNotifierProvider.family<
    UserBoomerangsByUserController, UserBoomerangsState, String>(
  UserBoomerangsByUserController.new,
);

class UserBoomerangsByUserController
    extends FamilyAsyncNotifier<UserBoomerangsState, String> {
  static const int _pageSize = 20;

  @override
  Future<UserBoomerangsState> build(String arg) async {
    // Start empty; caller calls fetchNext
    return UserBoomerangsState.initial;
  }

  Future<void> refresh() async {
    state = const AsyncData(UserBoomerangsState.initial);
    await fetchNext();
  }

  Future<void> fetchNext() async {
    final currentState = state.value ?? UserBoomerangsState.initial;
    if (currentState.isLoading || !currentState.hasMore) return;
    final userId = arg;
    state = AsyncData(currentState.copyWith(isLoading: true));
    try {
      final repo = ref.read(boomerangRepoProvider);
      final snap = await repo.fetchUserBoomerangsPage(
        userId: userId,
        startAfter: currentState.last,
        limit: _pageSize,
      );
      final nextDocs = [...currentState.docs, ...snap.docs];
      final nextLast =
          snap.docs.isNotEmpty ? snap.docs.last : currentState.last;
      final nextHasMore = snap.docs.length >= _pageSize;
      state = AsyncData(
        currentState.copyWith(
          docs: nextDocs,
          last: nextLast,
          hasMore: nextHasMore,
          isLoading: false,
        ),
      );
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}


