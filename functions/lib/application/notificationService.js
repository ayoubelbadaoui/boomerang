"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processNotification = processNotification;
exports.normalizePayload = normalizePayload;
const firebase_1 = require("../infrastructure/firebase");
const deviceTokenRepository_1 = require("../infrastructure/repositories/deviceTokenRepository");
const userRepository_1 = require("../infrastructure/repositories/userRepository");
const pushSender_1 = require("../infrastructure/push/pushSender");
const templates_1 = require("../domain/templates");
const rateLimiter_1 = require("./rateLimiter");
const constants_1 = require("../config/constants");
async function processNotification(targetUserId, raw) {
    const payload = normalizePayload(targetUserId, raw);
    if (!isSupportedType(payload.type)) {
        console.log('[notifications] skipping unsupported type', payload.type);
        return;
    }
    // Rate limit per user/type to reduce spam bursts
    const throttled = await (0, rateLimiter_1.shouldThrottle)(targetUserId, payload.type);
    if (throttled) {
        console.log('[notifications] throttled', { targetUserId, type: payload.type });
        return;
    }
    const [targetUser, actorUser, deviceTokens] = await Promise.all([
        (0, userRepository_1.fetchUserProfile)(targetUserId),
        payload.actorUserId ? (0, userRepository_1.fetchUserProfile)(payload.actorUserId) : undefined,
        (0, deviceTokenRepository_1.getUserDeviceTokens)(targetUserId),
    ]);
    if (!targetUser) {
        console.warn('[notifications] target user not found', targetUserId);
        return;
    }
    if (targetUser.pushEnabled === false) {
        console.log('[notifications] push disabled for user', targetUserId);
        return;
    }
    if (deviceTokens.length === 0) {
        console.log('[notifications] no device tokens for user', targetUserId);
        return;
    }
    const unreadSnap = await firebase_1.db
        .collection('users')
        .doc(targetUserId)
        .collection('notifications')
        .where('read', '==', false)
        .count()
        .get();
    const unreadCount = unreadSnap.data().count;
    const template = (0, templates_1.renderTemplate)(payload, actorUser);
    const message = buildPushMessage(payload, template, actorUser, unreadCount);
    await (0, pushSender_1.sendToUserDevices)(targetUserId, deviceTokens, message);
}
function normalizePayload(targetUserId, raw) {
    return {
        type: raw.type ?? 'unknown',
        actorUserId: raw.actorUserId,
        actorName: raw.actorName,
        actorAvatar: raw.actorAvatar,
        targetUserId,
        resourceId: (raw.resourceId ?? raw.boomerangId),
        resourceType: raw.resourceType,
        text: raw.text,
        createdAt: raw.createdAt,
    };
}
function isSupportedType(type) {
    return ['follow', 'follow_back', 'follow_request', 'like', 'comment', 'reply'].includes(type);
}
function buildPushMessage(payload, template, actorUser, badgeCount = 1) {
    const data = {
        type: payload.type,
    };
    if (payload.actorUserId)
        data.actorUserId = payload.actorUserId;
    if (payload.resourceId)
        data.resourceId = payload.resourceId;
    if (payload.resourceType)
        data.resourceType = payload.resourceType;
    if (actorUser?.avatarUrl)
        data.avatarUrl = actorUser.avatarUrl;
    const imageUrl = actorUser?.avatarUrl;
    return {
        notification: {
            title: template.title || constants_1.APP_NAME,
            body: template.body,
            ...(imageUrl ? { image: imageUrl } : {}),
        },
        data,
        apns: {
            payload: {
                aps: {
                    sound: 'default',
                    badge: badgeCount,
                    'mutable-content': 1,
                },
            },
            ...(imageUrl ? { fcmOptions: { image: imageUrl } } : {}),
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'boomerang_push',
                sound: 'default',
                ...(imageUrl ? { image: imageUrl } : {}),
            },
        },
        tokens: [],
    };
}
//# sourceMappingURL=notificationService.js.map