import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/features/feed/domain/ranking/ranking_policy.dart';
import 'package:boomerang/features/feed/domain/repositories/feed_repo.dart';
import 'package:boomerang/features/feed/infrastructure/firestore_feed_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';

import 'ranking/default_ranking_policy.dart';

/// Whether the v2 ranking pipeline is active. Wired through a provider so a
/// remote kill-switch can flip it without redeploying the app.
enum RankingFlag { enabled, disabled }

/// Compile-time default. Set to [RankingFlag.disabled] for a global rollback
/// without touching Firestore.
final rankingFeatureFlagProvider =
    Provider<RankingFlag>((_) => RankingFlag.enabled);

final rankingPolicyProvider = Provider<RankingPolicy>(
  (_) => const DefaultRankingPolicy(),
);

final feedRepoProvider = Provider<FeedRepo>((ref) {
  final repo = ref.watch(boomerangRepoProvider);
  return FirestoreFeedRepo(repo);
});
