# Feed Ranking — Design & Implementation

> Single source of truth for **Bug #9** (Home/Discovery should not be strict chronological). Read this before changing anything in `lib/features/feed/` or `functions/src/` related to ordering.

---

## 1. Problem statement

Before this change, the Boomerang feeds were strictly time-sorted:

| Surface | Query | Effect |
|---|---|---|
| Home | `boomerangs.where('userId', whereIn: following).orderBy('createdAt', desc)` | Stale repetitive scroll; one prolific author can monopolize the feed. |
| Discovery (no-query) | `boomerangs.where('ownerIsPrivate', false).orderBy('createdAt', desc)` | "Explore" looks identical to a global timeline; trending content is invisible. |
| Vertical pager | `fetchBoomerangsPage(...)` (chronological) | Tapping a post starts a chronological reel, ignoring relevance. |

We need **relevance-ranked, diversified, lightly randomized** feeds **without** breaking privacy (`firestore.rules → canReadBoomerang`), blocks, or pagination.

---

## 2. High-level design — a hybrid pipeline

```
                  ┌──────────────────────────────────┐
                  │ Cloud Function (scheduled, 15m)  │
                  │  recomputeRankScores             │
                  │  reads boomerangs (≤7 days),     │
                  │  writes  rankScore / rankUpdatedAt│
                  └──────────────────────────────────┘
                                  │ rankScore on docs
                                  ▼
┌─────────────┐   candidates    ┌──────────────────┐  RankedPosts  ┌──────────────────┐
│ Firestore   │ ──────────────► │ Infrastructure   │ ────────────► │ Application      │
│ boomerangs  │                 │ FirestoreFeedRepo│               │ FeedController + │
└─────────────┘                 │  • privacy gate  │               │ DefaultRanking-  │
                                │  • block filter  │               │ Policy           │
                                └──────────────────┘               └──────────────────┘
                                                                            │ FeedPage
                                                                            ▼
                                                                  ┌──────────────────┐
                                                                  │ Presentation     │
                                                                  │ HomeTab,         │
                                                                  │ DiscoverTab      │
                                                                  └──────────────────┘
```

**Server side** does the cheap, global thing: a single number per post that summarizes engagement × freshness.
**Client side** does everything personal: candidate fan-in, ranking, diversity, exploration jitter, paginated session state. Presentation stays pure rendering.

---

## 3. Why a Cloud Function (and only one)

| Option | Verdict | Reasoning |
|---|---|---|
| Pure client-side ranking | Insufficient on its own | Each device only sees its own slice; can't surface globally-popular content; every client repeats the same math. |
| Per-follower fan-out inbox (Instagram-style) | ❌ Reject (for now) | Heavy write amplification, complex delete/edit/privacy semantics, needs sharding. Out of scope for Bug #9. |
| **Scheduled CF that computes `rankScore` + client-side personalized rerank** | ✅ Chosen | Tiny server surface, no new collection, reuses existing CF infra. Client always personalizes. |

The function lives in `functions/src/infrastructure/listeners/rankingScheduler.ts` and follows the exact same shape as `onUserPrivacyChanged` (batched 500-writes, pinned `FUNCTIONS_REGION`). It is **additive**: clients that don't see a `rankScore` field fall back to the client-only formula.

---

## 4. Ranking policy

### 4.1 Score components (all normalized to roughly [0, 1])

| Component | Formula (per post) | Notes |
|---|---|---|
| `recency` | `exp(-ageHours / halfLife)` | half-life 24h for Home, 72h for Discovery. |
| `relationship` | 1.0 if `authorId ∈ following`, else 0.0 (extensible to mutual-like signal later) | Drives Home. |
| `engagement` | `(0.6·log1p(likes) + 0.4·log1p(commentsCount)) / 6` (saturates at ~ likes≈400) | Cap so a viral post doesn't drown the rest. |
| `serverScore` | `clamp01(serverRankScore)` if present, else 0 | Lets Cloud-Function-computed signals enter the mix on Discovery. |
| `exploration` | `Random(seed XOR postId.hashCode).nextDouble()` (bounded × weight) | Same `sessionSeed` keeps page-1 ordering stable when page-2 loads. |

### 4.2 Diversity penalties (applied during `rerank()`)

| Penalty | Trigger | Effect |
|---|---|---|
| `authorBurst` | Same `authorId` appears in any of the previous 2 slots, OR ≥ 3 of previous 5 | Demote: swap with the next eligible post within a 5-slot window. |
| `topicBurst` | Top hashtag matches ≥ 2 of previous 3 posts | Same demotion. |

### 4.3 Final score

```
final = w.recency      · recency
      + w.relationship · relationship
      + w.engagement   · engagement
      + w.serverScore  · serverScore
      + w.exploration  · exploration
```

Diversity penalties are post-sort, not part of the scalar score (otherwise a single penalty would always re-bury the same post — instead we *swap* within a window).

### 4.4 Weight presets (`RankingWeights`)

| Weight | Home | Discovery |
|---|---|---|
| `recency` | **0.40** | 0.20 |
| `relationship` | **0.35** | 0.05 |
| `engagement` | 0.15 | **0.30** |
| `serverScore` | 0.05 | **0.35** |
| `exploration` | 0.05 | 0.10 |
| `halfLifeHours` | 24 | 72 |
| `authorBurstWindow` | 2 | 3 |
| `topicBurstWindow` | 3 | 3 |

These live in **two mirrored places**:
- `lib/features/feed/domain/ranking/ranking_weights.dart` (Dart, used by the client)
- `functions/src/config/rankingWeights.ts` (TypeScript, used by the Cloud Function for `serverScore` only)

Mirror is intentional and small (4 numbers each side). Server only needs recency + engagement weights for its scalar; the rest is client personalization.

---

## 5. Candidate generation

### 5.1 Home

```
candidates =
   followingFeed(window=14 days, limit=60)         // existing path
 ∪ explorationFeed(rankScore desc, limit=20,       // new path
                   excluding authors already in following)
```

- `followingFeed` reuses `BoomerangRepo.fetchFollowingFeedPage` essentially unchanged.
- `explorationFeed` uses the new composite index `(ownerIsPrivate ASC, rankScore DESC)`.
- Deduped by id, capped at ~80 candidates per page.

### 5.2 Discovery (no query)

```
candidates =
   boomerangs where ownerIsPrivate==false
              orderBy rankScore desc
              limit 80
```

Fallback when too many docs lack `rankScore` (e.g. fresh dataset, function not yet running): the repo falls back to `orderBy createdAt desc` and the client computes engagement locally.

### 5.3 Privacy / block / mute

Filtering happens in the repo **before** scoring:

```
candidate is kept iff
    authorId ∉ blockedIds
 ∧  (ownerIsPrivate == false OR authorId == me OR authorId ∈ followingIds)
```

`firestore.rules → canReadBoomerang` independently enforces the same gate server-side, so even a tampered client cannot widen visibility. There is no mute concept yet; when it lands it slots in here.

---

## 6. Pagination & session consistency

`FeedController` (a Riverpod `AsyncNotifier`) holds:

```dart
state = AsyncValue<FeedPageState>
class FeedPageState {
  List<RankedPost> items;     // already shown to the user
  FeedCursor? nextCursor;     // surface-specific; opaque to UI
  bool hasMore;
  int sessionSeed;            // rotates on pull-to-refresh
  Set<String> seenIds;        // hard dedupe across all pages this session
}
```

- `nextCursor` is **opaque to presentation**. Domain types only (`int? lastScoreTimesK`, `int? lastCreatedAtMillis`). No `QueryDocumentSnapshot` leaks past infrastructure.
- `seenIds` lives in the controller, not in the cursor, so refresh can rotate the seed without losing block/dedupe.
- Pull-to-refresh: new `sessionSeed`, `seenIds` cleared, `nextCursor` cleared. Top items can re-shuffle.
- Load-more: same `sessionSeed`, append-only; filter out any candidate already in `seenIds`. The previously rendered page **never** reorders.

---

## 7. Feature flag & fallback

- `featureFlagProvider` (in application) returns `RankingFlag.enabled` or `.disabled` based on:
  1. A user-scoped doc `users/{uid}/meta/featureFlags.rankingV2` (boolean, optional).
  2. A global kill-switch `users/{uid}/meta/featureFlags.rankingV2Disabled`.
  3. A compile-time default (currently `enabled`).
- When disabled, `FeedController` returns the legacy chronological order **byte-identically** by calling `BoomerangRepo.fetchFollowingFeedPage` / `watchPublicBoomerangs` directly.
- The active ranking version (`v2` or `legacy`) is logged with every page so QA can compare.

---

## 8. Observability

`lib/features/feed/application/ranking/feed_metrics.dart` emits per-page:

| Metric | Definition |
|---|---|
| `feed_diversity_score` | `1 − maxRunLengthByAuthor / pageSize`. 1.0 = perfectly diverse, 0.0 = single-author run. |
| `repeated_author_run_length` | Longest consecutive run of the same author in the page. |
| `session_depth` | Number of pages fetched in this session. |
| `refresh_novelty_rate` | `|new_ids ∩ this_page| / pageSize` between consecutive refreshes. |
| `ranking_version` | `'v2'` or `'legacy'`. |

For now these go to `debugPrint`. They are designed to hook a real analytics sink later without changing call sites.

---

## 9. Layered file layout

```
lib/features/feed/
├── domain/
│   ├── entities/
│   │   └── ranked_post.dart                  // immutable RankedPost
│   ├── ranking/
│   │   ├── feed_surface.dart                 // enum FeedSurface { home, discovery }
│   │   ├── feed_page.dart                    // FeedPage + abstract FeedCursor
│   │   ├── ranking_weights.dart              // RankingWeights + .home / .discovery presets
│   │   ├── score_components.dart             // ScoreComponents
│   │   └── ranking_policy.dart               // abstract RankingPolicy
│   └── repositories/
│       └── feed_repo.dart                    // abstract FeedRepo, CandidatePool, HomeCursor, DiscoveryCursor
│
├── application/
│   ├── feed_controller.dart                  // AsyncNotifier<FeedPageState>
│   ├── feed_providers.dart                   // Riverpod providers + feature flag
│   └── ranking/
│       ├── default_ranking_policy.dart       // concrete RankingPolicy
│       ├── feed_metrics.dart                 // diversity / depth logging
│       └── session_seed.dart                 // stable per-(uid, surface) seed
│
├── infrastructure/
│   ├── boomerang_repo.dart                   // extended with fetchPublicByRankScorePage(...)
│   └── firestore_feed_repo.dart              // implements FeedRepo using BoomerangRepo
│
└── presentation/                             // unchanged structure, two widgets rewired
    ├── tabs/home_tab.dart                    // now watches homeFeedProvider
    └── tabs/discover_tab.dart                // _BmgGrid no-query branch watches discoveryFeedProvider
```

Cloud Functions side:

```
functions/src/
├── config/rankingWeights.ts                  // server-side weight constants
├── application/ranking/computeRankScore.ts   // pure (post, now, weights) → number
└── infrastructure/listeners/rankingScheduler.ts // pubsub.schedule('every 15 minutes')
```

---

## 10. Data contracts

### 10.1 `RankedPost` (domain)
```dart
class RankedPost {
  final String id;
  final String authorId;
  final DateTime? createdAt;
  final int likes;
  final int commentsCount;
  final List<String> hashtags;
  final bool ownerIsPrivate;
  final double? serverRankScore;     // null if CF hasn't run yet
  final Map<String, dynamic> raw;    // pass-through for existing card UI
}
```

`raw` exists so we don't rewrite every card widget. Presentation reads `raw['videoUrl']`, `raw['caption']`, etc. exactly as today.

### 10.2 `FeedPage` (domain)
```dart
class FeedPage {
  final List<RankedPost> items;
  final FeedCursor? nextCursor;
  final bool hasMore;
}
```

### 10.3 New Firestore fields on `boomerangs/{id}`
| Field | Type | Writer | Reader |
|---|---|---|---|
| `rankScore` | double (0..~10) | `rankingScheduler` Cloud Function | Discovery candidate query, scoring |
| `rankUpdatedAt` | Timestamp | `rankingScheduler` | Skip-write optimization, debug |

Both fields are nullable. The client tolerates their absence indefinitely.

### 10.4 New composite indexes (`firestore.indexes.json`)
| Fields | Used by |
|---|---|
| `(ownerIsPrivate ASC, rankScore DESC)` | Discovery feed candidate fetch |
| `(ownerIsPrivate ASC, rankUpdatedAt DESC)` | CF efficiency / debug |

---

## 11. Privacy & security audit

| Concern | Mitigation |
|---|---|
| Private post leaking into Discovery | Repo filter (`ownerIsPrivate == false`) **and** `firestore.rules` `canReadBoomerang` — defense in depth. |
| Blocked author appearing | Repo applies `blockedIds` filter before scoring; presentation re-applies via `blockedUsersProvider` like today. |
| Stale `ownerIsPrivate` after privacy toggle | Already handled by `onUserPrivacyChanged` CF (batched 500-write). Ranking only reads the field; it does not own it. |
| Cloud Function widening visibility | Function only writes `rankScore`, `rankUpdatedAt` on the post itself. No reads/writes against private collections. No new rule changes. |
| Server score becoming a side-channel | `rankScore` is computed from data already public on the doc (`likes`, `commentsCount`, `createdAt`). |

---

## 12. Rollout plan

1. Ship CF in shadow mode (writing `rankScore` on every run) — no behavior change.
2. Wait one CF cycle (~15 min) so most recent posts have a score.
3. Enable client `rankingV2` feature flag per-user (default `enabled` after smoke test).
4. Monitor `feed_diversity_score` and `refresh_novelty_rate` in debug logs.
5. Kill-switch path: set `users/{uid}/meta/featureFlags.rankingV2Disabled = true` to revert per user. A global rollback is `RankingFlag.disabled` default.

---

## 13. Out of scope (intentional)

- Per-follower materialized timelines (write-time fan-out).
- Per-edge interaction strength (last-comment-from-X, last-DM-from-X). Hook left in `relationship`.
- View counts / dwell time (no client emission today).
- Mute. Hidden behind the same privacy/block plumbing when added.
- Hashtag-search ranking (`watchByHashtagsAny`) — separate bug.
- Vertical pager ranking. The pager continues to use the legacy chronological fetch until a follow-up rewires it to consume `FeedController` state.

---

## 14. Test matrix

| Test | File |
|---|---|
| Recency monotonic with equal other signals | `test/feed/default_ranking_policy_test.dart` |
| Relationship dominates in Home weights | same |
| Engagement + server score dominate in Discovery weights | same |
| Author-burst: 5 posts by A, 1 by B → no run of 3 from A | same |
| Deterministic seed reproducibility | same |
| Different seed ⇒ different order | same |
| Private non-followed post never in output, even with max engagement | same |
| Page 1 / page 2 have zero duplicate ids | `test/feed/feed_controller_test.dart` (fake_cloud_firestore) |
| Refresh rotates seed but keeps top-quality items | same |
| Feature flag off ⇒ behavior matches `BoomerangRepo.fetchFollowingFeedPage` byte-for-byte | same |

`flutter analyze` must pass with zero new issues. `npm --prefix functions run build` must compile.
