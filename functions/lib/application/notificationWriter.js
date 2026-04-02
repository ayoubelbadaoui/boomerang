"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueNotification = enqueueNotification;
const firebase_1 = require("../infrastructure/firebase");
function stripUndefined(obj) {
    return Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== undefined));
}
/**
 * Writes a single notification doc to users/{userId}/notifications.
 * The onNotificationCreated trigger watches this path for push delivery.
 */
async function enqueueNotification(targetUserId, payload) {
    const createdAt = payload.createdAt ?? firebase_1.admin.firestore.FieldValue.serverTimestamp();
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
    await firebase_1.db.collection('users').doc(targetUserId).collection('notifications').add(item);
}
//# sourceMappingURL=notificationWriter.js.map