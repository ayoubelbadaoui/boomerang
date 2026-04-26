import { db, admin } from '../firebase';
import * as functions from 'firebase-functions/v1';
import { FUNCTIONS_REGION } from '../../config/constants';

const FIELDS = ['followersCount', 'followingCount', 'boomerangsCount', 'totalLikes'] as const;

interface UserFix {
  uid: string;
  fixes: { field: string; was: number; now: number }[];
}

/**
 * Single HTTP function that walks every user doc one by one,
 * counts the real followers, following, boomerangs, and total likes,
 * and overwrites the stored value when it's wrong.
 */
export const reconcileAllUsers = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (_req, res) => {
    functions.logger.info('reconcileAllUsers: starting');

    const fixed: UserFix[] = [];
    let usersProcessed = 0;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    while (true) {
      let query = db.collection('users')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(50);
      if (lastDoc) query = query.startAfter(lastDoc);

      const page = await query.get();
      if (page.empty) break;

      for (const userDoc of page.docs) {
        const uid = userDoc.id;
        const data = userDoc.data();
        usersProcessed++;

        const [realFollowers, realFollowing, bmgSnap] = await Promise.all([
          db.collection('followers').doc(uid).collection('users').count().get(),
          db.collection('following').doc(uid).collection('users').count().get(),
          db.collection('boomerangs').where('userId', '==', uid).select('likes').get(),
        ]);

        const realBoomerangs = bmgSnap.size;
        let realTotalLikes = 0;
        for (const doc of bmgSnap.docs) {
          realTotalLikes += ((doc.data().likes as number) ?? 0);
        }

        const real: Record<string, number> = {
          followersCount: realFollowers.data().count,
          followingCount: realFollowing.data().count,
          boomerangsCount: realBoomerangs,
          totalLikes: realTotalLikes,
        };

        const updates: Record<string, number> = {};
        const fixes: UserFix['fixes'] = [];

        for (const field of FIELDS) {
          const stored = (data[field] ?? 0) as number;
          if (stored !== real[field]) {
            updates[field] = real[field];
            fixes.push({ field, was: stored, now: real[field] });
          }
        }

        if (fixes.length > 0) {
          await db.collection('users').doc(uid).update(updates);
          fixed.push({ uid, fixes });
          functions.logger.info(`Fixed ${uid}:`, fixes);
        }
      }

      lastDoc = page.docs[page.docs.length - 1];
    }

    const result = {
      usersProcessed,
      usersFixed: fixed.length,
      details: fixed,
    };

    functions.logger.info('reconcileAllUsers: done', {
      usersProcessed,
      usersFixed: fixed.length,
    });

    res.status(200).send(result);
  });
