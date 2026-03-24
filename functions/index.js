const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Re-export existing TypeScript-compiled social notification functions
// (TS module handles initializeApp internally)
const tsExports = require("./lib/index");
Object.assign(exports, tsExports);

exports.onNewChatMessage = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const db = getFirestore();
    const messaging = getMessaging();

    const snap = event.data;
    if (!snap) return;

    const messageData = snap.data();
    const { senderId, text, type } = messageData;
    const conversationId = event.params.conversationId;

    const convDoc = await db
      .collection("conversations")
      .doc(conversationId)
      .get();

    if (!convDoc.exists) {
      console.warn(`Conversation ${conversationId} not found`);
      return;
    }

    const participants = convDoc.data().participants || [];
    const receivers = participants.filter((uid) => uid !== senderId);
    if (receivers.length === 0) return;

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderData = senderDoc.exists ? senderDoc.data() : {};
    const senderName =
      senderData.nickname || senderData.fullName || "Someone";
    const senderAvatar = senderData.avatarUrl || "";

    const body = type === "image" ? "📷 Sent a photo" : text || "New message";

    const tokens = [];
    for (const receiverId of receivers) {
      try {
        const tokenSnap = await db
          .collection("users")
          .doc(receiverId)
          .collection("deviceTokens")
          .get();
        for (const tokenDoc of tokenSnap.docs) {
          tokens.push(tokenDoc.id);
        }
      } catch (err) {
        console.error(`Failed to fetch tokens for ${receiverId}:`, err);
      }
    }

    if (tokens.length === 0) {
      console.log("No FCM tokens found for receivers");
      return;
    }

    const message = {
      notification: {
        title: senderName,
        body: body,
        ...(senderAvatar ? { image: senderAvatar } : {}),
      },
      data: {
        conversationId: conversationId,
        senderId: senderId,
        type: "chat_message",
        senderName: senderName,
        ...(senderAvatar ? { avatarUrl: senderAvatar } : {}),
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          ...(senderAvatar ? { image: senderAvatar } : {}),
        },
      },
      apns: {
        payload: {
          aps: { sound: "default", badge: 1, "mutable-content": 1 },
        },
        ...(senderAvatar ? { fcmOptions: { image: senderAvatar } } : {}),
      },
      tokens: tokens,
    };

    try {
      const response = await messaging.sendEachForMulticast(message);
      console.log(
        `Sent ${response.successCount}/${tokens.length} notifications`
      );

      if (response.failureCount > 0) {
        const tokensToRemove = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const code = resp.error?.code;
            if (
              code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered"
            ) {
              tokensToRemove.push(tokens[idx]);
            }
          }
        });
        for (const staleToken of tokensToRemove) {
          for (const receiverId of receivers) {
            try {
              await db
                .collection("users")
                .doc(receiverId)
                .collection("deviceTokens")
                .doc(staleToken)
                .delete();
            } catch (_) {}
          }
        }
      }
    } catch (err) {
      console.error("Error sending FCM notification:", err);
    }
  }
);
