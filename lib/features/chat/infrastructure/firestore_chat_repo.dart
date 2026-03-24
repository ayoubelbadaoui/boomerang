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
  }) async {
    final messageRef = _messages(conversationId).doc();
    final conversationRef = _conversations.doc(conversationId);

    final now = FieldValue.serverTimestamp();
    final typeStr = type == MessageType.image ? 'image' : 'text';
    final previewText = type == MessageType.image ? '📷 Photo' : text;

    final messageData = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'type': typeStr,
      'createdAt': now,
      'status': 'sent',
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

  // ── Image Upload ──────────────────────────────────────────────────────

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
}
