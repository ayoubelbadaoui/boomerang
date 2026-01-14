import { db } from '../firebase';

export async function getUserDeviceTokens(userId: string): Promise<string[]> {
  const snap = await db.collection('users').doc(userId).collection('deviceTokens').get();
  return snap.docs.map((d) => d.id);
}

export async function deleteDeviceTokens(userId: string, tokens: string[]): Promise<void> {
  const deletions = tokens.map((token) =>
    db.collection('users').doc(userId).collection('deviceTokens').doc(token).delete(),
  );
  await Promise.all(deletions);
}
