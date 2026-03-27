"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueNotification = enqueueNotification;
const firebase_1 = require("../infrastructure/firebase");
/** Removes keys whose value is undefined so Firestore doesn't reject the write. */
function stripUndefined(obj) {
    return Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== undefined));
}
/**
 * Writes a notification item to the canonical path watched by push delivery:
 * notifications/{userId}/items/{itemId}
 */
async function enqueueNotification(targetUserId, payload) {
    const canonical = firebase_1.db.collection('notifications').doc(targetUserId).collection('items');
    const createdAt = payload.createdAt ?? firebase_1.admin.firestore.FieldValue.serverTimestamp();
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
    const legacyRef = firebase_1.db.collection('users').doc(targetUserId).collection('notifications');
    await legacyRef.add(legacyItem);
}
//# sourceMappingURL=notificationWriter.js.map