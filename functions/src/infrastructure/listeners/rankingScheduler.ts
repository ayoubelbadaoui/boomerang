import * as functions from 'firebase-functions/v1';
import { admin, db } from '../firebase';
import { FUNCTIONS_REGION } from '../../config/constants';
import { SERVER_RANKING_WEIGHTS } from '../../config/rankingWeights';
import {
  computeRankScore,
  shouldWriteScore,
} from '../../application/ranking/computeRankScore';

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
export const recomputeRankScores = functions
  .region(FUNCTIONS_REGION)
  .pubsub.schedule(SCHEDULE)
  .onRun(async () => {
    const now = Date.now();
    const cutoffMs =
      now - SERVER_RANKING_WEIGHTS.recentWindowDays * 24 * 3_600_000;
    const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMs);

    // Two passes — public + private — so the index `(ownerIsPrivate ASC,
    // createdAt DESC)` is used for both. Private posts get their score so
    // visible-to-followers ranking on Home stays accurate.
    let totalScanned = 0;
    let totalWritten = 0;
    for (const privacyFlag of [false, true] as const) {
      const snap = await db
        .collection('boomerangs')
        .where('ownerIsPrivate', '==', privacyFlag)
        .where('createdAt', '>=', cutoff)
        .select('createdAt', 'likes', 'commentsCount', 'rankScore')
        .get();

      totalScanned += snap.size;
      if (snap.empty) continue;

      const pending: Promise<FirebaseFirestore.WriteResult[]>[] = [];
      let batch = db.batch();
      let count = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        const createdAt = data.createdAt as admin.firestore.Timestamp | null;
        if (createdAt == null) continue;

        const score = computeRankScore(
          {
            likes: (data.likes as number | undefined) ?? 0,
            commentsCount:
              (data.commentsCount as number | undefined) ?? 0,
            createdAtMs: createdAt.toMillis(),
          },
          now,
        );

        const previous = data.rankScore as number | undefined;
        if (!shouldWriteScore(previous ?? null, score)) continue;

        batch.update(doc.ref, {
          rankScore: score,
          rankUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
        totalWritten++;
        if (count >= BATCH_SIZE) {
          pending.push(batch.commit());
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) pending.push(batch.commit());
      await Promise.all(pending);
    }

    functions.logger.info(
      `[ranking] recomputeRankScores: scanned=${totalScanned} written=${totalWritten}`,
    );
    return null;
  });
