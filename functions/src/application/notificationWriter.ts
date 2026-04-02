import { admin, db } from '../infrastructure/firebase';
import { NotificationPayload } from '../domain/notificationTypes';

function stripUndefined<T extends Record<string, unknown>>(obj: T): T {
  return Object.fromEntries(
    Object.entries(obj).filter(([, v]) => v !== undefined),
  ) as T;
}

/**
 * Writes a single notification doc to users/{userId}/notifications.
 * The onNotificationCreated trigger watches this path for push delivery.
 */
export async function enqueueNotification(targetUserId: string, payload: NotificationPayload): Promise<void> {
  const createdAt = payload.createdAt ?? admin.firestore.FieldValue.serverTimestamp();

  const item = stripUndefined({
    type: payload.type,
    senderId: payload.actorUserId ?? '',
    actorUserId: payload.actorUserId,
    actorName: payload.actorName,
    actorAvatar: payload.actorAvatar,
    boomerangId: payload.resourceId,
    boomerangImage: payload.boomerangImage,
    commentId: payload.commentId,
    parentCommentId: payload.parentCommentId,
    replyId: payload.replyId,
    text: payload.text,
    read: false,
    createdAt,
  });

  await db.collection('users').doc(targetUserId).collection('notifications').add(item);
}
