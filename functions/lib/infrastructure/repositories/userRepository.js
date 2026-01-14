"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchUserProfile = fetchUserProfile;
const firebase_1 = require("../firebase");
async function fetchUserProfile(userId) {
    const snap = await firebase_1.db.collection('users').doc(userId).get();
    if (!snap.exists)
        return undefined;
    const data = snap.data() ?? {};
    return {
        id: userId,
        username: data.username ?? data.handle,
        pushEnabled: data.pushEnabled,
    };
}
//# sourceMappingURL=userRepository.js.map