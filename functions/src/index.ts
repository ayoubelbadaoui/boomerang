import * as functions from 'firebase-functions/v1';
import { onNotificationCreated } from './infrastructure/listeners/firestoreNotifications';
import { app } from './interfaces/http/app';
import { FUNCTIONS_REGION } from './config/constants';
import {
  onCommentCreated,
  onReplyCreated,
  onBoomerangLikeUpdated,
  onFollowRequestCreated,
  onFollowerAdded,
} from './infrastructure/listeners/socialTriggers';
import { onUserPrivacyChanged, backfillOwnerIsPrivate } from './infrastructure/listeners/privacySync';
import { reconcileAllUsers } from './infrastructure/reconciliation';

export { onNotificationCreated };
export {
  onCommentCreated,
  onReplyCreated,
  onBoomerangLikeUpdated,
  onFollowRequestCreated,
  onFollowerAdded,
};
export { onUserPrivacyChanged, backfillOwnerIsPrivate };
export { reconcileAllUsers };
export const api = functions.region(FUNCTIONS_REGION).https.onRequest(app);
