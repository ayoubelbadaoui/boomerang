"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SERVER_RANKING_WEIGHTS = void 0;
/**
 * Server-side ranking weights used by the scheduled `recomputeRankScores`
 * function. These produce the scalar `rankScore` stored on each post.
 *
 * Loose mirror of `lib/features/feed/domain/ranking/ranking_weights.dart`.
 * The server is intentionally limited to the *global* signals (freshness +
 * engagement); per-user personalization (relationship, exploration jitter,
 * diversity) stays on the client.
 */
exports.SERVER_RANKING_WEIGHTS = {
    recency: 0.5,
    engagement: 0.5,
    /** Half-life of the recency decay, in hours. */
    halfLifeHours: 36,
    /**
     * Window of posts the scheduler scores per cycle (in days). Older posts
     * have a vanishingly small recency component and aren't worth rewriting.
     */
    recentWindowDays: 7,
    /**
     * Minimum *relative* change required to overwrite `rankScore`. Skips
     * writes when the new score moved by less than 5% so the function is
     * cheap to run frequently.
     */
    minRelativeDelta: 0.05,
};
//# sourceMappingURL=rankingWeights.js.map