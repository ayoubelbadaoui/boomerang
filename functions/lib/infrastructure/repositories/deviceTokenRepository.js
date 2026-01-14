"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getUserDeviceTokens = getUserDeviceTokens;
exports.deleteDeviceTokens = deleteDeviceTokens;
const firebase_1 = require("../firebase");
async function getUserDeviceTokens(userId) {
    const snap = await firebase_1.db.collection('users').doc(userId).collection('deviceTokens').get();
    return snap.docs.map((d) => d.id);
}
async function deleteDeviceTokens(userId, tokens) {
    const deletions = tokens.map((token) => firebase_1.db.collection('users').doc(userId).collection('deviceTokens').doc(token).delete());
    await Promise.all(deletions);
}
//# sourceMappingURL=deviceTokenRepository.js.map