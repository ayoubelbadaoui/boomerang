"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.recomputeRankScores = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const firebase_1 = require("../firebase");
const constants_1 = require("../../config/constants");
const rankingWeights_1 = require("../../config/rankingWeights");
const computeRankScore_1 = require("../../application/ranking/computeRankScore");
const SCHEDULE = 'every 15 minutes';
const BATCH_SIZE = 500;
/**
 * Scheduled function that periodically recomputes the global `rankScore`
 * field on recent boomerangs. Reads are cheap (one collection scan windowed
 * to the last N days), writes are skipped when the score barely moved.
 *
 * Layered the same way as `onUserPrivacyChanged`:
 *   - pure scoring lives in `application/ranking/computeRankScore.ts`
 *   - this file is purely the IO-bound batcher.
 */
exports.recomputeRankScores = functions
    .region(constants_1.FUNCTIONS_REGION)
    .pubsub.schedule(SCHEDULE)
    .onRun(async () => {
    const now = Date.now();
    const cutoffMs = now - rankingWeights_1.SERVER_RANKING_WEIGHTS.recentWindowDays * 24 * 3600000;
    const cutoff = firebase_1.admin.firestore.Timestamp.fromMillis(cutoffMs);
    // Two passes — public + private — so the index `(ownerIsPrivate ASC,
    // createdAt DESC)` is used for both. Private posts get their score so
    // visible-to-followers ranking on Home stays accurate.
    let totalScanned = 0;
    let totalWritten = 0;
    for (const privacyFlag of [false, true]) {
        const snap = await firebase_1.db
            .collection('boomerangs')
            .where('ownerIsPrivate', '==', privacyFlag)
            .where('createdAt', '>=', cutoff)
            .select('createdAt', 'likes', 'commentsCount', 'rankScore')
            .get();
        totalScanned += snap.size;
        if (snap.empty)
            continue;
        const pending = [];
        let batch = firebase_1.db.batch();
        let count = 0;
        for (const doc of snap.docs) {
            const data = doc.data();
            const createdAt = data.createdAt;
            if (createdAt == null)
                continue;
            const score = (0, computeRankScore_1.computeRankScore)({
                likes: data.likes ?? 0,
                commentsCount: data.commentsCount ?? 0,
                createdAtMs: createdAt.toMillis(),
            }, now);
            const previous = data.rankScore;
            if (!(0, computeRankScore_1.shouldWriteScore)(previous ?? null, score))
                continue;
            batch.update(doc.ref, {
                rankScore: score,
                rankUpdatedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
            });
            count++;
            totalWritten++;
            if (count >= BATCH_SIZE) {
                pending.push(batch.commit());
                batch = firebase_1.db.batch();
                count = 0;
            }
        }
        if (count > 0)
            pending.push(batch.commit());
        await Promise.all(pending);
    }
    functions.logger.info(`[ranking] recomputeRankScores: scanned=${totalScanned} written=${totalWritten}`);
    return null;
});
//# sourceMappingURL=rankingScheduler.js.map