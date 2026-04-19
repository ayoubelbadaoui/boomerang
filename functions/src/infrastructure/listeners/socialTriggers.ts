import * as functions from 'firebase-functions/v1';
import { db } from '../firebase';
import { FUNCTIONS_REGION } from '../../config/constants';
import { enqueueNotification } from '../../application/notificationWriter';
import { fetchUserProfile } from '../repositories/userRepository';

const boomerangsCol = db.collection('boomerangs');

export const onCommentCreated = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('boomerangs/{boomerangId}/comments/{commentId}')
  .onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const actorUserId = (data.userId as string | undefined) || '';
    if (!actorUserId) return;

    const boomerangId = ctx.params.boomerangId as string;
    const postSnap = await boomerangsCol.doc(boomerangId).get();
    const ownerId = (postSnap.data()?.userId as string | undefined) || '';
    const boomerangImage = postSnap.data()?.imageUrl as string | undefined;
    if (!ownerId || ownerId === actorUserId) return;

    await enqueueNotification(ownerId, {
      type: 'comment',
      actorUserId,
      actorName: data.userName as string | undefined,
      resourceId: boomerangId,
      resourceType: 'boomerang',
      text: data.text as string | undefined,
      boomerangImage,
      commentId: ctx.params.commentId as string,
    });
  });

export const onReplyCreated = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('boomerangs/{boomerangId}/comments/{commentId}/replies/{replyId}')
  .onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const actorUserId = (data.userId as string | undefined) || '';
    if (!actorUserId) return;
    const boomerangId = ctx.params.boomerangId as string;
    const commentId = ctx.params.commentId as string;

    const [postSnap, parentSnap] = await Promise.all([
      boomerangsCol.doc(boomerangId).get(),
      boomerangsCol.doc(boomerangId).collection('comments').doc(commentId).get(),
    ]);

    const ownerId = (postSnap.data()?.userId as string | undefined) || '';
    const parentAuthorId = (parentSnap.data()?.userId as string | undefined) || '';
    const boomerangImage = postSnap.data()?.imageUrl as string | undefined;

    const targets = new Set<string>();
    if (ownerId && ownerId !== actorUserId) targets.add(ownerId);
    if (parentAuthorId && parentAuthorId !== actorUserId) targets.add(parentAuthorId);

    await Promise.all(
      Array.from(targets).map((target) =>
        enqueueNotification(target, {
          type: target === ownerId ? 'comment' : 'reply',
          actorUserId,
          actorName: data.userName as string | undefined,
          resourceId: boomerangId,
          resourceType: 'boomerang',
          text: data.text as string | undefined,
          boomerangImage,
          commentId,
          parentCommentId: commentId,
          replyId: ctx.params.replyId as string,
        }),
      ),
    );
  });

export const onBoomerangLikeUpdated = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('boomerangs/{boomerangId}')
  .onUpdate(async (change, ctx) => {
    const before = (change.before.data()?.likedBy as string[] | undefined) ?? [];
    const after = (change.after.data()?.likedBy as string[] | undefined) ?? [];
    if (after.length <= before.length) return; // only care about added likes

    const added = after.filter((u) => !before.includes(u));
    if (added.length === 0) return;

    const boomerangId = ctx.params.boomerangId as string;
    const ownerId = (change.after.data()?.userId as string | undefined) || '';
    const boomerangImage = change.after.data()?.imageUrl as string | undefined;
    if (!ownerId) return;

    const ownerProfilePromise = fetchUserProfile(ownerId); // prefetch for push check

    const actorProfiles = await Promise.all(added.map((id) => fetchUserProfile(id)));
    const notifications = added
      .map((actorId, idx) => {
        if (actorId === ownerId) return undefined;
        const actorProfile = actorProfiles[idx];
        return enqueueNotification(ownerId, {
          type: 'like',
          actorUserId: actorId,
          actorName: actorProfile?.username,
          resourceId: boomerangId,
          resourceType: 'boomerang',
          boomerangImage,
        });
      })
      .filter(Boolean) as Promise<void>[];

    await ownerProfilePromise; // ensure fetch completes (not strictly required)
    await Promise.all(notifications);
  });

export const onFollowRequestCreated = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('users/{receiverId}/followRequests/{senderId}')
  .onCreate(async (snap, ctx) => {
    const receiverId = ctx.params.receiverId as string;
    const senderId = ctx.params.senderId as string;
    const actorProfile = await fetchUserProfile(senderId);
    await enqueueNotification(receiverId, {
      type: 'follow_request',
      actorUserId: senderId,
      actorName: actorProfile?.username,
    });
  });

export const onFollowerAdded = functions
  .region(FUNCTIONS_REGION)
  .firestore.document('followers/{targetUserId}/users/{followerId}')
  .onCreate(async (snap, ctx) => {
    const targetUserId = ctx.params.targetUserId as string;
    const followerId = ctx.params.followerId as string;
    if (!targetUserId || !followerId || targetUserId === followerId) return;

    const followerProfile = await fetchUserProfile(followerId);

    // Always notify target of new follower
    await enqueueNotification(targetUserId, {
      type: 'follow',
      actorUserId: followerId,
      actorName: followerProfile?.username,
    });

    // If target already follows follower, also send follow_back to follower
    const mutualSnap = await db
      .collection('followers')
      .doc(followerId)
      .collection('users')
      .doc(targetUserId)
      .get();
    if (mutualSnap.exists) {
      await enqueueNotification(followerId, {
        type: 'follow_back',
        actorUserId: targetUserId,
      });
    }
  });
