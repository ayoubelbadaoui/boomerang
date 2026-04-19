import * as functions from 'firebase-functions/v1';
import { db } from '../firebase';
import { FUNCTIONS_REGION } from '../../config/constants';

/**
 * When a user toggles isPrivate, propagate the new value to all their
 * boomerangs so Firestore queries and rules stay consistent.
 * Batches writes in groups of 500 (Firestore batch limit).
 */
export const onUserPrivacyChanged = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('users/{uid}')
  .onUpdate(async (change, ctx) => {
    const before = change.before.data();
    const after = change.after.data();

    const wasPrev = before?.isPrivate === true;
    const isNow = after?.isPrivate === true;
    if (wasPrev === isNow) return;

    const uid = ctx.params.uid as string;
    const posts = await db
      .collection('boomerangs')
      .where('userId', '==', uid)
      .select()
      .get();

    if (posts.empty) return;

    const pending: Promise<FirebaseFirestore.WriteResult[]>[] = [];
    let batch = db.batch();
    let count = 0;

    for (const doc of posts.docs) {
      batch.update(doc.ref, { ownerIsPrivate: isNow });
      count++;
      if (count >= 500) {
        pending.push(batch.commit());
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) pending.push(batch.commit());

    await Promise.all(pending);

    functions.logger.info(
      `Privacy sync: updated ${posts.size} boomerangs for user ${uid} → ownerIsPrivate=${isNow}`,
    );
  });

/**
 * One-time callable function to backfill ownerIsPrivate on legacy posts
 * that were created before the field existed.
 * Call once via: firebase functions:shell → backfillOwnerIsPrivate()
 * or via HTTP after deploy.
 */
export const backfillOwnerIsPrivate = functions
  .region(FUNCTIONS_REGION)
  .https.onRequest(async (_req, res) => {
    const allPosts = await db.collection('boomerangs').select('userId', 'ownerIsPrivate').get();
    let updated = 0;

    const pending: Promise<FirebaseFirestore.WriteResult[]>[] = [];
    let batch = db.batch();
    let count = 0;

    for (const doc of allPosts.docs) {
      const data = doc.data();
      if (data.ownerIsPrivate === true || data.ownerIsPrivate === false) continue;

      const userId = data.userId as string | undefined;
      let isPrivate = false;
      if (userId) {
        const userSnap = await db.collection('users').doc(userId).get();
        isPrivate = userSnap.data()?.isPrivate === true;
      }

      batch.update(doc.ref, { ownerIsPrivate: isPrivate });
      count++;
      updated++;
      if (count >= 500) {
        pending.push(batch.commit());
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) pending.push(batch.commit());
    await Promise.all(pending);

    const msg = `Backfill complete: ${updated} of ${allPosts.size} posts updated.`;
    functions.logger.info(msg);
    res.status(200).send(msg);
  });
