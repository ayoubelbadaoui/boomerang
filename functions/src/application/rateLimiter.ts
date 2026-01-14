import { admin, db } from '../infrastructure/firebase';
import { NOTIFICATION_THROTTLE_MS } from '../config/constants';

const collection = db.collection('notificationRateLimits');

export async function shouldThrottle(userId: string, type: string): Promise<boolean> {
  const docId = `${userId}_${type}`;
  const docRef = collection.doc(docId);

  let throttled = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const now = admin.firestore.Timestamp.now();
    const lastSentAt = snap.get('lastSentAt') as admin.firestore.Timestamp | undefined;
    if (lastSentAt && now.toMillis() - lastSentAt.toMillis() < NOTIFICATION_THROTTLE_MS) {
      throttled = true;
      return;
    }
    tx.set(docRef, { lastSentAt: now }, { merge: true });
  });

  return throttled;
}
