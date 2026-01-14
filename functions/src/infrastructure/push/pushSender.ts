import { messaging } from '../firebase';
import { deleteDeviceTokens } from '../repositories/deviceTokenRepository';
import { admin } from '../firebase';

export type PushPayload = admin.messaging.MulticastMessage;

export async function sendToUserDevices(userId: string, tokens: string[], message: PushPayload): Promise<void> {
  if (tokens.length === 0) return;
  const response = await messaging.sendEachForMulticast({ ...message, tokens });

  const tokensToDelete: string[] = [];
  response.responses.forEach((res, idx) => {
    if (!res.success && res.error) {
      const code = (res.error as any).code as string;
      const shouldDelete =
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-argument') ||
        code.includes('mismatched-credential');
      if (shouldDelete) tokensToDelete.push(tokens[idx]);
    }
  });

  if (tokensToDelete.length > 0) {
    await deleteDeviceTokens(userId, tokensToDelete);
  }
}
