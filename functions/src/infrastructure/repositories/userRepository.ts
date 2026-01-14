import { db } from '../firebase';
import { UserProfile } from '../../domain/notificationTypes';

export async function fetchUserProfile(userId: string): Promise<UserProfile | undefined> {
  const snap = await db.collection('users').doc(userId).get();
  if (!snap.exists) return undefined;
  const data = snap.data() ?? {};
  return {
    id: userId,
    username: (data.username as string | undefined) ?? (data.handle as string | undefined),
    pushEnabled: data.pushEnabled as boolean | undefined,
  };
}
