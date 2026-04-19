"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.shouldThrottle = shouldThrottle;
const firebase_1 = require("../infrastructure/firebase");
const constants_1 = require("../config/constants");
const collection = firebase_1.db.collection('notificationRateLimits');
async function shouldThrottle(userId, type) {
    const docId = `${userId}_${type}`;
    const docRef = collection.doc(docId);
    let throttled = false;
    await firebase_1.db.runTransaction(async (tx) => {
        const snap = await tx.get(docRef);
        const now = firebase_1.admin.firestore.Timestamp.now();
        const lastSentAt = snap.get('lastSentAt');
        if (lastSentAt && now.toMillis() - lastSentAt.toMillis() < constants_1.NOTIFICATION_THROTTLE_MS) {
            throttled = true;
            return;
        }
        tx.set(docRef, { lastSentAt: now }, { merge: true });
    });
    return throttled;
}
//# sourceMappingURL=rateLimiter.js.map