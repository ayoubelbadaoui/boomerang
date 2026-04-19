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
exports.backfillOwnerIsPrivate = exports.onUserPrivacyChanged = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const firebase_1 = require("../firebase");
const constants_1 = require("../../config/constants");
/**
 * When a user toggles isPrivate, propagate the new value to all their
 * boomerangs so Firestore queries and rules stay consistent.
 * Batches writes in groups of 500 (Firestore batch limit).
 */
exports.onUserPrivacyChanged = functions
    .region(constants_1.FUNCTIONS_REGION)
    .firestore.document('users/{uid}')
    .onUpdate(async (change, ctx) => {
    const before = change.before.data();
    const after = change.after.data();
    const wasPrev = before?.isPrivate === true;
    const isNow = after?.isPrivate === true;
    if (wasPrev === isNow)
        return;
    const uid = ctx.params.uid;
    const posts = await firebase_1.db
        .collection('boomerangs')
        .where('userId', '==', uid)
        .select()
        .get();
    if (posts.empty)
        return;
    const pending = [];
    let batch = firebase_1.db.batch();
    let count = 0;
    for (const doc of posts.docs) {
        batch.update(doc.ref, { ownerIsPrivate: isNow });
        count++;
        if (count >= 500) {
            pending.push(batch.commit());
            batch = firebase_1.db.batch();
            count = 0;
        }
    }
    if (count > 0)
        pending.push(batch.commit());
    await Promise.all(pending);
    functions.logger.info(`Privacy sync: updated ${posts.size} boomerangs for user ${uid} → ownerIsPrivate=${isNow}`);
});
/**
 * One-time callable function to backfill ownerIsPrivate on legacy posts
 * that were created before the field existed.
 * Call once via: firebase functions:shell → backfillOwnerIsPrivate()
 * or via HTTP after deploy.
 */
exports.backfillOwnerIsPrivate = functions
    .region(constants_1.FUNCTIONS_REGION)
    .https.onRequest(async (_req, res) => {
    const allPosts = await firebase_1.db.collection('boomerangs').select('userId', 'ownerIsPrivate').get();
    let updated = 0;
    const pending = [];
    let batch = firebase_1.db.batch();
    let count = 0;
    for (const doc of allPosts.docs) {
        const data = doc.data();
        if (data.ownerIsPrivate === true || data.ownerIsPrivate === false)
            continue;
        const userId = data.userId;
        let isPrivate = false;
        if (userId) {
            const userSnap = await firebase_1.db.collection('users').doc(userId).get();
            isPrivate = userSnap.data()?.isPrivate === true;
        }
        batch.update(doc.ref, { ownerIsPrivate: isPrivate });
        count++;
        updated++;
        if (count >= 500) {
            pending.push(batch.commit());
            batch = firebase_1.db.batch();
            count = 0;
        }
    }
    if (count > 0)
        pending.push(batch.commit());
    await Promise.all(pending);
    const msg = `Backfill complete: ${updated} of ${allPosts.size} posts updated.`;
    functions.logger.info(msg);
    res.status(200).send(msg);
});
//# sourceMappingURL=privacySync.js.map