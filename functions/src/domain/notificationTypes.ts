export type NotificationType =
  | 'follow'
  | 'follow_back'
  | 'follow_request'
  | 'like'
  | 'comment'
  | 'reply';

export interface NotificationPayload {
  type: NotificationType | string;
  actorUserId?: string;
  targetUserId?: string;
  actorName?: string;
  actorAvatar?: string;
  resourceId?: string;
  resourceType?: 'boomerang' | 'comment' | 'reply' | string;
  text?: string;
  boomerangImage?: string;
  commentId?: string;
  parentCommentId?: string;
  replyId?: string;
  createdAt?: FirebaseFirestore.Timestamp;
}

export interface UserProfile {
  id: string;
  username?: string;
  pushEnabled?: boolean;
}

export interface TemplateResult {
  title: string;
  body: string;
}
