"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.app = void 0;
const express_1 = __importDefault(require("express"));
const notificationService_1 = require("../../application/notificationService");
exports.app = (0, express_1.default)();
exports.app.use(express_1.default.json());
exports.app.get('/health', (_req, res) => {
    res.status(200).send({ status: 'ok' });
});
// Manual trigger to test push delivery via HTTPS callable/HTTP endpoint.
exports.app.post('/notifications/test', async (req, res) => {
    try {
        const { userId, payload } = req.body;
        if (!userId || !payload) {
            return res.status(400).send({ error: 'userId and payload are required' });
        }
        await (0, notificationService_1.processNotification)(userId, payload);
        return res.status(200).send({ status: 'queued' });
    }
    catch (err) {
        console.error('[notifications] test endpoint failed', err);
        return res.status(500).send({ error: 'internal_error' });
    }
});
//# sourceMappingURL=app.js.map