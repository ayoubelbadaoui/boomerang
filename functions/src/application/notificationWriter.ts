import { admin, db } from '../infrastructure/firebase';
import { NotificationPayload } from '../domain/notificationTypes';

/** Removes keys whose value is undefined so Firestore doesn't reject the write. */
function stripUndefined<T extends Record<string, unknown>>(obj: T): T {
  return Object.fromEntries(
    Object.entries(obj).filter(([, v]) => v !== undefined),
  ) as T;
}

/**
 * Writes a notification item to the canonical path watched by push delivery:
 * notifications/{userId}/items/{itemId}
 */
export async function enqueueNotification(targetUserId: string, payload: NotificationPayload): Promise<void> {
  const canonical = db.collection('notifications').doc(targetUserId).collection('items');
  const createdAt = payload.createdAt ?? admin.firestore.FieldValue.serverTimestamp();

  const canonicalItem = stripUndefined({ ...payload, createdAt, read: false });
  await canonical.add(canonicalItem);

  const legacyItem = stripUndefined({
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

  const legacyRef = db.collection('users').doc(targetUserId).collection('notifications');
  await legacyRef.add(legacyItem);
}
