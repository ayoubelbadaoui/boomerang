import { NotificationType, NotificationPayload, TemplateResult, UserProfile } from './notificationTypes';
import { APP_NAME } from '../config/constants';

type TemplateBuilder = (payload: NotificationPayload, actor?: UserProfile) => TemplateResult;

const fallbackActor = (actor?: UserProfile): string => actor?.username ?? actor?.id ?? 'Someone';

const templates: Record<NotificationType, TemplateBuilder> = {
  follow: (_payload, actor) => ({
    title: 'New follower',
    body: `${fallbackActor(actor)} followed you`,
  }),
  follow_back: (_payload, actor) => ({
    title: 'Follow back',
    body: `${fallbackActor(actor)} followed you back`,
  }),
  follow_request: (_payload, actor) => ({
    title: 'Follow request',
    body: `${fallbackActor(actor)} requested to follow you`,
  }),
  like: (_payload, actor) => ({
    title: 'New like',
    body: `${fallbackActor(actor)} liked your post`,
  }),
  comment: (payload, actor) => ({
    title: 'New comment',
    body: `${fallbackActor(actor)} commented: ${truncateText(payload.text)}`,
  }),
  reply: (payload, actor) => ({
    title: 'New reply',
    body: `${fallbackActor(actor)} replied: ${truncateText(payload.text)}`,
  }),
};

const truncateText = (text?: string, max = 80): string => {
  if (!text) return '';
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
};

export function renderTemplate(payload: NotificationPayload, actor?: UserProfile): TemplateResult {
  const template = templates[payload.type as NotificationType];
  if (template) return template(payload, actor);
  return {
    title: APP_NAME,
    body: 'You have a new notification',
  };
}
