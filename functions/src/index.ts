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
import { reconcileAllUsers, normalizeBoomerangFields } from './infrastructure/reconciliation';
import { recomputeRankScores } from './infrastructure/listeners/rankingScheduler';

export { onNotificationCreated };
export {
  onCommentCreated,
  onReplyCreated,
  onBoomerangLikeUpdated,
  onFollowRequestCreated,
  onFollowerAdded,
};
export { onUserPrivacyChanged, backfillOwnerIsPrivate };
export { reconcileAllUsers, normalizeBoomerangFields };
export { recomputeRankScores };
export const api = functions.region(FUNCTIONS_REGION).https.onRequest(app);
