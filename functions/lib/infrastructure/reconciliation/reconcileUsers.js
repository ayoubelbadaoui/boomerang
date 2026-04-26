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
exports.reconcileAllUsers = void 0;
const firebase_1 = require("../firebase");
const functions = __importStar(require("firebase-functions/v1"));
const constants_1 = require("../../config/constants");
const FIELDS = ['followersCount', 'followingCount', 'boomerangsCount', 'totalLikes'];
/**
 * Single HTTP function that walks every user doc one by one,
 * counts the real followers, following, boomerangs, and total likes,
 * and overwrites the stored value when it's wrong.
 */
exports.reconcileAllUsers = functions
    .region(constants_1.FUNCTIONS_REGION)
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (_req, res) => {
    functions.logger.info('reconcileAllUsers: starting');
    const fixed = [];
    let usersProcessed = 0;
    let lastDoc;
    while (true) {
        let query = firebase_1.db.collection('users')
            .orderBy(firebase_1.admin.firestore.FieldPath.documentId())
            .limit(50);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const page = await query.get();
        if (page.empty)
            break;
        for (const userDoc of page.docs) {
            const uid = userDoc.id;
            const data = userDoc.data();
            usersProcessed++;
            const [realFollowers, realFollowing, bmgSnap] = await Promise.all([
                firebase_1.db.collection('followers').doc(uid).collection('users').count().get(),
                firebase_1.db.collection('following').doc(uid).collection('users').count().get(),
                firebase_1.db.collection('boomerangs').where('userId', '==', uid).select('likes').get(),
            ]);
            const realBoomerangs = bmgSnap.size;
            let realTotalLikes = 0;
            for (const doc of bmgSnap.docs) {
                realTotalLikes += (doc.data().likes ?? 0);
            }
            const real = {
                followersCount: realFollowers.data().count,
                followingCount: realFollowing.data().count,
                boomerangsCount: realBoomerangs,
                totalLikes: realTotalLikes,
            };
            const updates = {};
            const fixes = [];
            for (const field of FIELDS) {
                const stored = (data[field] ?? 0);
                if (stored !== real[field]) {
                    updates[field] = real[field];
                    fixes.push({ field, was: stored, now: real[field] });
                }
            }
            if (fixes.length > 0) {
                await firebase_1.db.collection('users').doc(uid).update(updates);
                fixed.push({ uid, fixes });
                functions.logger.info(`Fixed ${uid}:`, fixes);
            }
        }
        lastDoc = page.docs[page.docs.length - 1];
    }
    const result = {
        usersProcessed,
        usersFixed: fixed.length,
        details: fixed,
    };
    functions.logger.info('reconcileAllUsers: done', {
        usersProcessed,
        usersFixed: fixed.length,
    });
    res.status(200).send(result);
});
//# sourceMappingURL=reconcileUsers.js.map