import { db } from '../firebase';
import { UserProfile } from '../../domain/notificationTypes';

export async function fetchUserProfile(userId: string): Promise<UserProfile | undefined> {
  const snap = await db.collection('users').doc(userId).get();
  if (!snap.exists) return undefined;
  const data = snap.data() ?? {};
  const name =
    (data.nickname as string | undefined) ??
    (data.fullName as string | undefined) ??
    (data.username as string | undefined) ??
    (data.handle as string | undefined);
  return {
    id: userId,
    username: name,
    avatarUrl: (data.avatarUrl as string | undefined) ?? undefined,
    pushEnabled: data.pushEnabled as boolean | undefined,
  };
}
