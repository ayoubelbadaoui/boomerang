import { admin } from '../infrastructure/firebase';
import { getUserDeviceTokens } from '../infrastructure/repositories/deviceTokenRepository';
import { fetchUserProfile } from '../infrastructure/repositories/userRepository';
import { sendToUserDevices } from '../infrastructure/push/pushSender';
import { NotificationPayload, NotificationType } from '../domain/notificationTypes';
import { renderTemplate } from '../domain/templates';
import { shouldThrottle } from './rateLimiter';
import { APP_NAME } from '../config/constants';

type RawNotification = FirebaseFirestore.DocumentData;

export async function processNotification(targetUserId: string, raw: RawNotification): Promise<void> {
  const payload = normalizePayload(targetUserId, raw);
  if (!isSupportedType(payload.type)) {
    console.log('[notifications] skipping unsupported type', payload.type);
    return;
  }

  // Rate limit per user/type to reduce spam bursts
  const throttled = await shouldThrottle(targetUserId, payload.type);
  if (throttled) {
    console.log('[notifications] throttled', { targetUserId, type: payload.type });
    return;
  }

  const [targetUser, actorUser, deviceTokens] = await Promise.all([
    fetchUserProfile(targetUserId),
    payload.actorUserId ? fetchUserProfile(payload.actorUserId) : undefined,
    getUserDeviceTokens(targetUserId),
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

  const template = renderTemplate(payload, actorUser);
  const message = buildPushMessage(payload, template, actorUser);
  await sendToUserDevices(targetUserId, deviceTokens, message);
}

function normalizePayload(targetUserId: string, raw: RawNotification): NotificationPayload {
  return {
    type: (raw.type as string) ?? 'unknown',
    actorUserId: raw.actorUserId as string | undefined,
    actorName: raw.actorName as string | undefined,
    actorAvatar: raw.actorAvatar as string | undefined,
    targetUserId,
    resourceId: raw.resourceId as string | undefined,
    resourceType: raw.resourceType as string | undefined,
    text: raw.text as string | undefined,
    createdAt: raw.createdAt as FirebaseFirestore.Timestamp | undefined,
  };
}

function isSupportedType(type: string): type is NotificationType {
  return ['follow', 'follow_back', 'follow_request', 'like', 'comment', 'reply'].includes(type);
}

function buildPushMessage(
  payload: NotificationPayload,
  template: { title: string; body: string },
  actorUser?: { avatarUrl?: string },
): admin.messaging.MulticastMessage {
  const data: Record<string, string> = {
    type: payload.type,
  };
  if (payload.actorUserId) data.actorUserId = payload.actorUserId;
  if (payload.resourceId) data.resourceId = payload.resourceId;
  if (payload.resourceType) data.resourceType = payload.resourceType;
  if (actorUser?.avatarUrl) data.avatarUrl = actorUser.avatarUrl;

  const imageUrl = actorUser?.avatarUrl;

  return {
    notification: {
      title: template.title || APP_NAME,
      body: template.body,
      ...(imageUrl ? { image: imageUrl } : {}),
    },
    data,
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
          'mutable-content': 1,
        },
      },
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        ...(imageUrl ? { image: imageUrl } : {}),
      },
    },
    tokens: [],
  };
}
