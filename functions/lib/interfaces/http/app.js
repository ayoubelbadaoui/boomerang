"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.app = void 0;
const express_1 = __importDefault(require("express"));
const notificationService_1 = require("../../application/notificationService");
const firebase_1 = require("../../infrastructure/firebase");
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
const SUFFIX_WORDS = ['goat', 'real', 'prime', 'nova', 'zen', 'x', 'pro', 'mx'];
function sanitizeUsername(raw) {
    let value = raw.trim().toLowerCase().replace(/[^a-z0-9._]/g, '_');
    value = value.replace(/^_+|_+$/g, '');
    if (value.length > 20)
        value = value.substring(0, 20);
    if (value.length < 3)
        value = `${value.padEnd(3, 'x')}`;
    return value;
}
function toUserRow(uid, data) {
    const nicknameLower = (data.nicknameLower ?? '').toString().trim();
    const usernameLower = (data.usernameLower ?? '').toString().trim();
    const nickname = (data.nickname ?? '').toString().trim();
    const username = (data.username ?? '').toString().trim();
    const email = (data.email ?? '').toString().trim();
    const primary = nicknameLower || usernameLower || sanitizeUsername(nickname || username);
    if (!primary)
        return null;
    const createdAt = data.createdAt;
    const createdAtMs = createdAt?.toMillis?.() ?? Number.MAX_SAFE_INTEGER;
    return {
        uid,
        email,
        username: sanitizeUsername(primary),
        hasUsernameField: Object.prototype.hasOwnProperty.call(data, 'username'),
        hasNicknameField: Object.prototype.hasOwnProperty.call(data, 'nickname'),
        createdAtMs,
    };
}
async function buildTakenUsernames() {
    const taken = new Set();
    const [usersSnap, loginAliasesSnap] = await Promise.all([
        firebase_1.db.collection('users').get(),
        firebase_1.db.collection('login_usernames').get(),
    ]);
    for (const doc of usersSnap.docs) {
        const row = toUserRow(doc.id, doc.data());
        if (row != null)
            taken.add(row.username);
    }
    for (const doc of loginAliasesSnap.docs) {
        const id = doc.id.trim().toLowerCase();
        if (id.length > 0)
            taken.add(id);
    }
    return taken;
}
function randomSuffix() {
    const word = SUFFIX_WORDS[Math.floor(Math.random() * SUFFIX_WORDS.length)];
    const num = Math.floor(10 + Math.random() * 90);
    return Math.random() < 0.5 ? `${num}` : `${word}_${num}`;
}
function buildCandidate(base) {
    const suffix = randomSuffix();
    const normalizedBase = sanitizeUsername(base);
    const maxBaseLen = Math.max(3, 20 - (suffix.length + 1));
    return sanitizeUsername(`${normalizedBase.substring(0, maxBaseLen)}_${suffix}`);
}
exports.app.get('/admin/usernames/deduplicate', async (req, res) => {
    try {
        const execute = req.query.execute === 'true';
        const dryRun = !execute;
        const usersSnap = await firebase_1.db.collection('users').get();
        const rows = usersSnap.docs
            .map((doc) => toUserRow(doc.id, doc.data()))
            .filter((row) => row != null);
        const byUsername = new Map();
        for (const row of rows) {
            const list = byUsername.get(row.username) ?? [];
            list.push(row);
            byUsername.set(row.username, list);
        }
        const duplicates = [...byUsername.entries()]
            .filter(([, list]) => list.length > 1)
            .map(([username, list]) => {
            const sorted = [...list].sort((a, b) => {
                if (a.createdAtMs != b.createdAtMs)
                    return a.createdAtMs - b.createdAtMs;
                return a.uid.localeCompare(b.uid);
            });
            return { username, users: sorted };
        });
        if (duplicates.length === 0) {
            return res.status(200).send({
                dryRun,
                message: 'No duplicate usernames found.',
                duplicateGroups: 0,
                updatedUsers: 0,
            });
        }
        const taken = await buildTakenUsernames();
        const plan = [];
        for (const group of duplicates) {
            const keeper = group.users[0];
            plan.push({
                uid: keeper.uid,
                oldUsername: group.username,
                newUsername: group.username,
                email: keeper.email,
                keep: true,
                hasUsernameField: keeper.hasUsernameField,
                hasNicknameField: keeper.hasNicknameField,
            });
            taken.add(group.username);
            for (const user of group.users.slice(1)) {
                let candidate = buildCandidate(group.username);
                let attempts = 0;
                while (taken.has(candidate) && attempts < 300) {
                    candidate = buildCandidate(group.username);
                    attempts++;
                }
                if (taken.has(candidate)) {
                    return res.status(500).send({
                        error: 'candidate_exhausted',
                        message: 'Could not generate a unique username candidate after many attempts.',
                        uid: user.uid,
                        base: group.username,
                    });
                }
                taken.add(candidate);
                plan.push({
                    uid: user.uid,
                    oldUsername: group.username,
                    newUsername: candidate,
                    email: user.email,
                    keep: false,
                    hasUsernameField: user.hasUsernameField,
                    hasNicknameField: user.hasNicknameField,
                });
            }
        }
        if (dryRun) {
            return res.status(200).send({
                dryRun: true,
                duplicateGroups: duplicates.length,
                updatedUsers: plan.filter((p) => !p.keep).length,
                preview: plan,
            });
        }
        const batch = firebase_1.db.batch();
        for (const p of plan) {
            const userRef = firebase_1.db.collection('users').doc(p.uid);
            if (!p.keep) {
                const updateData = {
                    nickname: p.newUsername,
                    nicknameLower: p.newUsername,
                    updatedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                };
                if (p.hasUsernameField) {
                    updateData.username = p.newUsername;
                    updateData.usernameLower = p.newUsername;
                }
                if (!p.hasNicknameField) {
                    updateData.nickname = p.newUsername;
                }
                batch.set(userRef, updateData, { merge: true });
            }
            if (p.email.length > 0) {
                const aliasRef = firebase_1.db.collection('login_usernames').doc(p.newUsername);
                batch.set(aliasRef, {
                    uid: p.uid,
                    email: p.email,
                    alias: p.newUsername,
                    updatedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        }
        await batch.commit();
        return res.status(200).send({
            dryRun: false,
            duplicateGroups: duplicates.length,
            updatedUsers: plan.filter((p) => !p.keep).length,
            updated: plan,
        });
    }
    catch (err) {
        console.error('[admin] username deduplicate failed', err);
        return res.status(500).send({ error: 'internal_error' });
    }
});
//# sourceMappingURL=app.js.map