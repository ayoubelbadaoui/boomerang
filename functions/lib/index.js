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
exports.api = exports.recomputeRankScores = exports.reconcileAllUsers = exports.backfillOwnerIsPrivate = exports.onUserPrivacyChanged = exports.onFollowerAdded = exports.onFollowRequestCreated = exports.onBoomerangLikeUpdated = exports.onReplyCreated = exports.onCommentCreated = exports.onNotificationCreated = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const firestoreNotifications_1 = require("./infrastructure/listeners/firestoreNotifications");
Object.defineProperty(exports, "onNotificationCreated", { enumerable: true, get: function () { return firestoreNotifications_1.onNotificationCreated; } });
const app_1 = require("./interfaces/http/app");
const constants_1 = require("./config/constants");
const socialTriggers_1 = require("./infrastructure/listeners/socialTriggers");
Object.defineProperty(exports, "onCommentCreated", { enumerable: true, get: function () { return socialTriggers_1.onCommentCreated; } });
Object.defineProperty(exports, "onReplyCreated", { enumerable: true, get: function () { return socialTriggers_1.onReplyCreated; } });
Object.defineProperty(exports, "onBoomerangLikeUpdated", { enumerable: true, get: function () { return socialTriggers_1.onBoomerangLikeUpdated; } });
Object.defineProperty(exports, "onFollowRequestCreated", { enumerable: true, get: function () { return socialTriggers_1.onFollowRequestCreated; } });
Object.defineProperty(exports, "onFollowerAdded", { enumerable: true, get: function () { return socialTriggers_1.onFollowerAdded; } });
const privacySync_1 = require("./infrastructure/listeners/privacySync");
Object.defineProperty(exports, "onUserPrivacyChanged", { enumerable: true, get: function () { return privacySync_1.onUserPrivacyChanged; } });
Object.defineProperty(exports, "backfillOwnerIsPrivate", { enumerable: true, get: function () { return privacySync_1.backfillOwnerIsPrivate; } });
const reconciliation_1 = require("./infrastructure/reconciliation");
Object.defineProperty(exports, "reconcileAllUsers", { enumerable: true, get: function () { return reconciliation_1.reconcileAllUsers; } });
const rankingScheduler_1 = require("./infrastructure/listeners/rankingScheduler");
Object.defineProperty(exports, "recomputeRankScores", { enumerable: true, get: function () { return rankingScheduler_1.recomputeRankScores; } });
exports.api = functions.region(constants_1.FUNCTIONS_REGION).https.onRequest(app_1.app);
//# sourceMappingURL=index.js.map