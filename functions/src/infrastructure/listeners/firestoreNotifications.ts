import * as functions from 'firebase-functions/v1';
import { processNotification } from '../../application/notificationService';
import { FUNCTIONS_REGION } from '../../config/constants';

export const onNotificationCreated = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('users/{userId}/notifications/{itemId}')
  .onCreate(async (snap, ctx): Promise<void> => {
    const userId = ctx.params.userId as string;
    await processNotification(userId, snap.data() ?? {});
  });
