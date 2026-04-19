import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:boomerang/features/chat/domain/chat_repo.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:boomerang/features/chat/infrastructure/dto/conversation_dto.dart';
import 'package:boomerang/features/chat/infrastructure/dto/message_dto.dart';

class FirestoreChatRepo implements ChatRepo {
  FirestoreChatRepo(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> _messages(String conversationId) =>
      _conversations.doc(conversationId).collection('messages');

  // ── Conversations ─────────────────────────────────────────────────────

  @override
  Stream<List<ConversationEntity>> streamConversations(String userId) {
    return _conversations
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ConversationDto.fromFirestore(doc).toEntity())
            .toList())
        .handleError((e, st) {
      debugPrint('streamConversations error: $e');
    });
  }

  @override
  Future<String> getOrCreateConversation(List<String> participantIds) async {
    final sorted = List<String>.from(participantIds)..sort();

    final existing = await _conversations
        .where('participants', isEqualTo: sorted)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return existing.docs.first.id;

    final now = Timestamp.now();
    final unreadCount = {for (final uid in sorted) uid: 0};

    final doc = await _conversations.add({
      'participants': sorted,
      'lastMessage': '',
      'lastMessageAt': now,
      'lastMessageSenderId': '',
      'unreadCount': unreadCount,
      'createdAt': now,
      'pinnedBy': <String>[],
    });
    return doc.id;
  }

  // ── Messages ──────────────────────────────────────────────────────────

  @override
  Stream<List<MessageEntity>> streamMessages(
    String conversationId, {
    int limit = 20,
  }) {
    return _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MessageDto.fromFirestore(doc).toEntity())
            .toList())
        .handleError((e, st) {
      debugPrint('streamMessages error: $e');
    });
  }

  @override
  Future<MessageEntity> sendMessage(
    String conversationId, {
    required String senderId,
    required String text,
    required MessageType type,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    MessageType? replyToType,
    int? audioDurationMs,
  }) async {
    final messageRef = _messages(conversationId).doc();
    final conversationRef = _conversations.doc(conversationId);

    final now = FieldValue.serverTimestamp();
    final typeStr = MessageDto.typeToString(type);

    String previewText;
    switch (type) {
      case MessageType.image:
        previewText = '📷 Photo';
        break;
      case MessageType.gif:
        previewText = 'GIF';
        break;
      case MessageType.audio:
        previewText = '🎤 Voice message';
        break;
      case MessageType.text:
        previewText = text;
        break;
    }

    final messageData = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'type': typeStr,
      'createdAt': now,
      'status': 'sent',
      'isUnsent': false,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (replyToType != null)
        'replyToType': MessageDto.typeToString(replyToType),
      if (audioDurationMs != null) 'audioDurationMs': audioDurationMs,
    };

    final conversationSnap = await conversationRef.get();
    final participants =
        List<String>.from(conversationSnap.data()?['participants'] ?? []);

    final unreadUpdates = <String, dynamic>{};
    for (final uid in participants) {
      if (uid != senderId) {
        unreadUpdates['unreadCount.$uid'] = FieldValue.increment(1);
      }
    }

    final batch = _firestore.batch();
    batch.set(messageRef, messageData);
    batch.update(conversationRef, {
      'lastMessage': previewText,
      'lastMessageAt': now,
      'lastMessageSenderId': senderId,
      ...unreadUpdates,
    });
    await batch.commit();

    return MessageEntity(
      id: messageRef.id,
      senderId: senderId,
      text: text,
      type: type,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      replyToType: replyToType,
      audioDurationMs: audioDurationMs,
    );
  }

  @override
  Future<List<MessageEntity>> loadMoreMessages(
    String conversationId, {
    required DateTime before,
    int limit = 20,
  }) async {
    final snapshot = await _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .startAfter([Timestamp.fromDate(before)])
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => MessageDto.fromFirestore(doc).toEntity())
        .toList();
  }

  @override
  Future<void> markMessagesAsSeen(
    String conversationId,
    String userId,
  ) async {
    final snapshot = await _messages(conversationId)
        .where('status', whereIn: ['sent', 'delivered'])
        .get();

    if (snapshot.docs.isEmpty) {
      await _conversations
          .doc(conversationId)
          .update({'unreadCount.$userId': 0});
      return;
    }

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      if (doc.data()['senderId'] != userId) {
        batch.update(doc.reference, {'status': 'seen'});
      }
    }
    batch.update(
      _conversations.doc(conversationId),
      {'unreadCount.$userId': 0},
    );
    await batch.commit();
  }

  // ── Unsend ─────────────────────────────────────────────────────────────

  @override
  Future<void> unsendMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final messageRef = _messages(conversationId).doc(messageId);
    final conversationRef = _conversations.doc(conversationId);

    await messageRef.update({
      'text': '',
      'type': 'text',
      'isUnsent': true,
      'replyToMessageId': FieldValue.delete(),
      'replyToText': FieldValue.delete(),
      'replyToSenderId': FieldValue.delete(),
      'replyToType': FieldValue.delete(),
      'audioDurationMs': FieldValue.delete(),
    });

    final convSnap = await conversationRef.get();
    final convData = convSnap.data();
    if (convData != null) {
      final latestMsg = await _messages(conversationId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (latestMsg.docs.isNotEmpty &&
          latestMsg.docs.first.id == messageId) {
        await conversationRef.update({'lastMessage': 'Message unsent'});
      }
    }
  }

  // ── Delete single message ────────────────────────────────────────────

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final messageRef = _messages(conversationId).doc(messageId);
    final conversationRef = _conversations.doc(conversationId);

    await messageRef.delete();

    final latestSnap = await _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestSnap.docs.isEmpty) {
      await conversationRef.update({
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
      });
    } else {
      final latest = MessageDto.fromFirestore(latestSnap.docs.first);
      final entity = latest.toEntity();
      String previewText;
      if (entity.isUnsent) {
        previewText = 'Message unsent';
      } else {
        switch (entity.type) {
          case MessageType.image:
            previewText = '📷 Photo';
            break;
          case MessageType.gif:
            previewText = 'GIF';
            break;
          case MessageType.audio:
            previewText = '🎤 Voice message';
            break;
          case MessageType.text:
            previewText = entity.text;
            break;
        }
      }
      await conversationRef.update({
        'lastMessage': previewText,
        'lastMessageAt': latestSnap.docs.first.data()['createdAt'],
        'lastMessageSenderId': entity.senderId,
      });
    }
  }

  // ── Pin / Unpin conversation ─────────────────────────────────────────

  @override
  Future<void> pinConversation({
    required String conversationId,
    required String userId,
  }) async {
    await _conversations.doc(conversationId).update({
      'pinnedBy': FieldValue.arrayUnion([userId]),
    });
  }

  @override
  Future<void> unpinConversation({
    required String conversationId,
    required String userId,
  }) async {
    await _conversations.doc(conversationId).update({
      'pinnedBy': FieldValue.arrayRemove([userId]),
    });
  }

  // ── Delete conversation ────────────────────────────────────────────────

  @override
  Future<void> deleteConversation({
    required String conversationId,
    required String userId,
  }) async {
    final convRef = _conversations.doc(conversationId);
    final snap = await convRef.get();
    final participants =
        List<String>.from(snap.data()?['participants'] ?? []);

    final isLastParticipant =
        participants.length <= 1 && participants.contains(userId);

    if (isLastParticipant) {
      final messagesSnap = await _messages(conversationId).get();

      final batchOps = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      var count = 0;

      for (final doc in messagesSnap.docs) {
        currentBatch.delete(doc.reference);
        count++;
        if (count >= 500) {
          batchOps.add(currentBatch);
          currentBatch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) batchOps.add(currentBatch);

      for (final batch in batchOps) {
        await batch.commit();
      }

      await convRef.delete();
    } else {
      await convRef.update({
        'participants': FieldValue.arrayRemove([userId]),
      });
    }
  }

  @override
  Future<void> deleteConversations({
    required List<String> conversationIds,
    required String userId,
  }) async {
    await Future.wait(
      conversationIds.map(
        (id) => deleteConversation(conversationId: id, userId: userId),
      ),
    );
  }

  // ── Media uploads ──────────────────────────────────────────────────────

  @override
  Future<String> uploadChatImage(
    String conversationId,
    String localPath,
  ) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref('chat_images/$conversationId/$fileName');
    await ref.putFile(File(localPath));
    return ref.getDownloadURL();
  }

  @override
  Future<String> uploadChatAudio(
    String conversationId,
    String localPath,
  ) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
    final ref = _storage.ref('chat_audio/$conversationId/$fileName');
    await ref.putFile(File(localPath));
    return ref.getDownloadURL();
  }
}
