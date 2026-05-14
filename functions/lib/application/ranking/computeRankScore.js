"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeRankScore = computeRankScore;
exports.shouldWriteScore = shouldWriteScore;
const rankingWeights_1 = require("../../config/rankingWeights");
const LIKES_SATURATION = 6.0; // log1p(~400) ≈ 6
const COMMENTS_SATURATION = 6.0;
/**
 * Pure function: given the engagement counters and creation time, returns
 * a scalar score in roughly [0, 1] that the client treats as `serverScore`.
 *
 * No IO, no Firestore access — easy to unit-test.
 */
function computeRankScore(post, nowMs, weights = rankingWeights_1.SERVER_RANKING_WEIGHTS) {
    const ageHours = Math.max(0, (nowMs - post.createdAtMs) / 3600000);
    const recency = Math.exp(-ageHours / weights.halfLifeHours);
    const likesPart = Math.log(1 + Math.max(0, post.likes)) / LIKES_SATURATION;
    const commentsPart = Math.log(1 + Math.max(0, post.commentsCount)) / COMMENTS_SATURATION;
    const engagement = clamp01(0.6 * likesPart + 0.4 * commentsPart);
    return clamp01(weights.recency * recency + weights.engagement * engagement);
}
function clamp01(v) {
    if (Number.isNaN(v))
        return 0;
    if (v < 0)
        return 0;
    if (v > 1)
        return 1;
    return v;
}
/**
 * Whether the score moved enough to be worth a Firestore write. Treats
 * `previous == null` as a forced write so freshly-created posts get their
 * first score on the next pass.
 */
function shouldWriteScore(previous, next, weights = rankingWeights_1.SERVER_RANKING_WEIGHTS) {
    if (previous == null)
        return true;
    const denom = Math.max(0.0001, Math.abs(previous));
    const delta = Math.abs(next - previous) / denom;
    return delta >= weights.minRelativeDelta;
}
//# sourceMappingURL=computeRankScore.js.map