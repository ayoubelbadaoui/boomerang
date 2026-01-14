"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueNotification = enqueueNotification;
const firebase_1 = require("../infrastructure/firebase");
/**
 * Writes a notification item to the canonical path watched by push delivery:
 * notifications/{userId}/items/{itemId}
 */
async function enqueueNotification(targetUserId, payload) {
    const canonical = firebase_1.db.collection('notifications').doc(targetUserId).collection('items');
    const createdAt = payload.createdAt ?? firebase_1.admin.firestore.FieldValue.serverTimestamp();
    const item = { ...payload, createdAt, read: false };
    // Write to canonical collection used by push
    await canonical.add(item);
    // Mirror to legacy path the app inbox reads: users/{uid}/notifications
    const legacyRef = firebase_1.db.collection('users').doc(targetUserId).collection('notifications');
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
//# sourceMappingURL=notificationWriter.js.map