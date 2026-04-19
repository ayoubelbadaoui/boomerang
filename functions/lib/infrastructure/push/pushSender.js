"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendToUserDevices = sendToUserDevices;
const firebase_1 = require("../firebase");
const deviceTokenRepository_1 = require("../repositories/deviceTokenRepository");
async function sendToUserDevices(userId, tokens, message) {
    if (tokens.length === 0)
        return;
    const response = await firebase_1.messaging.sendEachForMulticast({ ...message, tokens });
    const tokensToDelete = [];
    response.responses.forEach((res, idx) => {
        if (!res.success && res.error) {
            const code = res.error.code;
            const shouldDelete = code.includes('registration-token-not-registered') ||
                code.includes('invalid-argument') ||
                code.includes('mismatched-credential');
            if (shouldDelete)
                tokensToDelete.push(tokens[idx]);
        }
    });
    if (tokensToDelete.length > 0) {
        await (0, deviceTokenRepository_1.deleteDeviceTokens)(userId, tokensToDelete);
    }
}
//# sourceMappingURL=pushSender.js.map