import { admin, db } from '../infrastructure/firebase';
import { NotificationPayload } from '../domain/notificationTypes';

/**
 * Writes a notification item to the canonical path watched by push delivery:
 * notifications/{userId}/items/{itemId}
 */
export async function enqueueNotification(targetUserId: string, payload: NotificationPayload): Promise<void> {
  const canonical = db.collection('notifications').doc(targetUserId).collection('items');
  const createdAt = payload.createdAt ?? admin.firestore.FieldValue.serverTimestamp();
  const item = { ...payload, createdAt, read: false };

  // Write to canonical collection used by push
  await canonical.add(item);

  // Mirror to legacy path the app inbox reads: users/{uid}/notifications
  const legacyRef = db.collection('users').doc(targetUserId).collection('notifications');
  await legacyRef.add({
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
}
