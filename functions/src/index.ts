import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

admin.initializeApp();
const db = admin.firestore();

type NotificationItem = {
  type: 'follow' | 'like' | 'comment' | string;
  actorUserId?: string;
  actorName?: string;
  actorAvatar?: string;
  boomerangId?: string;
  boomerangImage?: string;
  createdAt?: admin.firestore.FieldValue;
  text?: string;
};

async function getUserDeviceTokens(userId: string): Promise<string[]> {
  const snap = await db
    .collection('users')
    .doc(userId)
    .collection('deviceTokens')
    .get();
  return snap.docs.map((d) => d.id);
}

async function sendMulticastAndCleanup(userId: string, tokens: string[], message: admin.messaging.MulticastMessage) {
  if (tokens.length === 0) return;
  const res = await admin.messaging().sendEachForMulticast({ ...message, tokens });
  const deletions: Promise<FirebaseFirestore.WriteResult>[] = [];
  res.responses.forEach((r, idx) => {
    if (!r.success) {
      const code = (r.error && (r.error as any).code) || '';
      const shouldDelete =
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-argument');
      if (shouldDelete) {
        const token = tokens[idx];
        const ref = db.collection('users').doc(userId).collection('deviceTokens').doc(token);
        deletions.push(ref.delete());
      }
    }
  });
  await Promise.all(deletions);
}

function buildMessageForNotification(userId: string, item: NotificationItem): admin.messaging.MulticastMessage {
  const baseData: Record<string, string> = {
    type: item.type,
    actorUserId: item.actorUserId ?? '',
    boomerangId: item.boomerangId ?? '',
  };

  let title = 'Boomerang';
  let body = 'You have a new notification';

  if (item.type === 'follow') {
    title = 'New follower';
    body = `${item.actorName ?? 'Someone'} followed you`;
  } else if (item.type === 'like') {
    title = 'New like';
    body = `${item.actorName ?? 'Someone'} liked your boomerang`;
  } else if (item.type === 'comment') {
    title = 'New comment';
    body = `${item.actorName ?? 'Someone'} commented on your boomerang`;
  }

  const message: admin.messaging.MulticastMessage = {
    notification: {
      title,
      body,
    },
    data: baseData,
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
      },
    },
    tokens: [], // filled by caller
  };
  return message;
}

export const onNotificationCreated = functions.firestore
  .document('notifications/{userId}/items/{itemId}')
  .onCreate(async (snap, ctx) => {
    const userId = ctx.params.userId as string;
    const data = snap.data() as NotificationItem;
    const tokens = await getUserDeviceTokens(userId);
    if (tokens.length === 0) return;
    const message = buildMessageForNotification(userId, data);
    await sendMulticastAndCleanup(userId, tokens, { ...message, tokens });
  });


