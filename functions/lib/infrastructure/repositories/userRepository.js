"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchUserProfile = fetchUserProfile;
const firebase_1 = require("../firebase");
async function fetchUserProfile(userId) {
    const snap = await firebase_1.db.collection('users').doc(userId).get();
    if (!snap.exists)
        return undefined;
    const data = snap.data() ?? {};
    const name = data.nickname ??
        data.fullName ??
        data.username ??
        data.handle;
    return {
        id: userId,
        username: name,
        avatarUrl: data.avatarUrl ?? undefined,
        pushEnabled: data.pushEnabled,
    };
}
//# sourceMappingURL=userRepository.js.map