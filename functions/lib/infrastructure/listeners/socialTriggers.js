"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onFollowerAdded = exports.onFollowRequestCreated = exports.onBoomerangLikeUpdated = exports.onReplyCreated = exports.onCommentCreated = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const firebase_1 = require("../firebase");
const constants_1 = require("../../config/constants");
const notificationWriter_1 = require("../../application/notificationWriter");
const userRepository_1 = require("../repositories/userRepository");
const boomerangsCol = firebase_1.db.collection('boomerangs');
exports.onCommentCreated = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('boomerangs/{boomerangId}/comments/{commentId}')
    .onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const actorUserId = data.userId || '';
    if (!actorUserId)
        return;
    const boomerangId = ctx.params.boomerangId;
    const postSnap = await boomerangsCol.doc(boomerangId).get();
    const ownerId = postSnap.data()?.userId || '';
    const boomerangImage = postSnap.data()?.imageUrl;
    if (!ownerId || ownerId === actorUserId)
        return;
    await (0, notificationWriter_1.enqueueNotification)(ownerId, {
        type: 'comment',
        actorUserId,
        actorName: data.userName,
        resourceId: boomerangId,
        resourceType: 'boomerang',
        text: data.text,
        boomerangImage,
        commentId: ctx.params.commentId,
    });
});
exports.onReplyCreated = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('boomerangs/{boomerangId}/comments/{commentId}/replies/{replyId}')
    .onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const actorUserId = data.userId || '';
    if (!actorUserId)
        return;
    const boomerangId = ctx.params.boomerangId;
    const commentId = ctx.params.commentId;
    const [postSnap, parentSnap] = await Promise.all([
        boomerangsCol.doc(boomerangId).get(),
        boomerangsCol.doc(boomerangId).collection('comments').doc(commentId).get(),
    ]);
    const ownerId = postSnap.data()?.userId || '';
    const parentAuthorId = parentSnap.data()?.userId || '';
    const boomerangImage = postSnap.data()?.imageUrl;
    const targets = new Set();
    if (ownerId && ownerId !== actorUserId)
        targets.add(ownerId);
    if (parentAuthorId && parentAuthorId !== actorUserId)
        targets.add(parentAuthorId);
    await Promise.all(Array.from(targets).map((target) => (0, notificationWriter_1.enqueueNotification)(target, {
        type: target === ownerId ? 'comment' : 'reply',
        actorUserId,
        actorName: data.userName,
        resourceId: boomerangId,
        resourceType: 'boomerang',
        text: data.text,
        boomerangImage,
        commentId,
        parentCommentId: commentId,
        replyId: ctx.params.replyId,
    })));
});
exports.onBoomerangLikeUpdated = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('boomerangs/{boomerangId}')
    .onUpdate(async (change, ctx) => {
    const before = change.before.data()?.likedBy ?? [];
    const after = change.after.data()?.likedBy ?? [];
    if (after.length <= before.length)
        return; // only care about added likes
    const added = after.filter((u) => !before.includes(u));
    if (added.length === 0)
        return;
    const boomerangId = ctx.params.boomerangId;
    const ownerId = change.after.data()?.userId || '';
    const boomerangImage = change.after.data()?.imageUrl;
    if (!ownerId)
        return;
    const ownerProfilePromise = (0, userRepository_1.fetchUserProfile)(ownerId); // prefetch for push check
    const actorProfiles = await Promise.all(added.map((id) => (0, userRepository_1.fetchUserProfile)(id)));
    const notifications = added
        .map((actorId, idx) => {
        if (actorId === ownerId)
            return undefined;
        const actorProfile = actorProfiles[idx];
        return (0, notificationWriter_1.enqueueNotification)(ownerId, {
            type: 'like',
            actorUserId: actorId,
            actorName: actorProfile?.username,
            resourceId: boomerangId,
            resourceType: 'boomerang',
            boomerangImage,
        });
    })
        .filter(Boolean);
    await ownerProfilePromise; // ensure fetch completes (not strictly required)
    await Promise.all(notifications);
});
exports.onFollowRequestCreated = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('users/{receiverId}/followRequests/{senderId}')
    .onCreate(async (snap, ctx) => {
    const receiverId = ctx.params.receiverId;
    const senderId = ctx.params.senderId;
    const actorProfile = await (0, userRepository_1.fetchUserProfile)(senderId);
    await (0, notificationWriter_1.enqueueNotification)(receiverId, {
        type: 'follow_request',
        actorUserId: senderId,
        actorName: actorProfile?.username,
    });
});
exports.onFollowerAdded = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('followers/{targetUserId}/users/{followerId}')
    .onCreate(async (snap, ctx) => {
    const targetUserId = ctx.params.targetUserId;
    const followerId = ctx.params.followerId;
    if (!targetUserId || !followerId || targetUserId === followerId)
        return;
    const followerProfile = await (0, userRepository_1.fetchUserProfile)(followerId);
    // Always notify target of new follower
    await (0, notificationWriter_1.enqueueNotification)(targetUserId, {
        type: 'follow',
        actorUserId: followerId,
        actorName: followerProfile?.username,
    });
    // If target already follows follower, also send follow_back to follower
    const mutualSnap = await firebase_1.db
        .collection('followers')
        .doc(followerId)
        .collection('users')
        .doc(targetUserId)
        .get();
    if (mutualSnap.exists) {
        await (0, notificationWriter_1.enqueueNotification)(followerId, {
            type: 'follow_back',
            actorUserId: targetUserId,
        });
    }
});
//# sourceMappingURL=socialTriggers.js.map