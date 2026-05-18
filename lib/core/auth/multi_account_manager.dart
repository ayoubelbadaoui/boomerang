import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';

import 'session_storage.dart';
import 'user_session.dart';

/// Orchestrates multi-account storage, switching, and removal.
class MultiAccountManager {
  MultiAccountManager({required this.storage, required this.firebaseAuth});

  final SessionStorage storage;
  final FirebaseAuth firebaseAuth;

  // ── Add / update ──────────────────────────────────────────────────────

  Future<void> addAccount(UserSession session, {String? password}) async {
    dev.log(
      '[multi-account] addAccount START uid=${session.uid} '
      'email=${session.email} hasPassword=${password != null}',
    );

    final sessions = await storage.getSessions();
    dev.log(
      '[multi-account] addAccount: existing sessions count=${sessions.length}',
    );

    final hadBefore = sessions.length;
    sessions.removeWhere((s) => s.uid == session.uid);
    sessions.add(session);

    dev.log(
      '[multi-account] addAccount: after merge count=${sessions.length} '
      '(was $hadBefore) uids=${sessions.map((s) => s.uid.substring(0, 6)).join(",")}',
    );

    final sessionsSaved = await storage.saveSessions(sessions);
    if (!sessionsSaved) {
      throw StateError('Failed to persist accounts');
    }
    final activeSaved = await storage.setActiveAccountId(session.uid);
    if (!activeSaved) {
      throw StateError('Failed to persist active account');
    }
    if (password != null) {
      final credsSaved = await storage.saveCredentials(
        session.uid,
        session.email,
        password,
      );
      if (!credsSaved) {
        throw StateError('Failed to persist account credentials');
      }
    }
    dev.log('[multi-account] addAccount DONE for ${session.email}');
  }

  Future<void> updateAccountProfile(
    String uid, {
    String? displayName,
    String? photoUrl,
  }) async {
    final sessions = await storage.getSessions();
    final idx = sessions.indexWhere((s) => s.uid == uid);
    if (idx == -1) return;
    sessions[idx] = sessions[idx].copyWith(
      displayName: displayName,
      photoUrl: photoUrl,
    );
    await storage.saveSessions(sessions);
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<List<UserSession>> getAccounts() async {
    final accounts = await storage.getSessions();
    dev.log(
      '[multi-account] getAccounts: ${accounts.length} accounts '
      '${accounts.map((s) => "${s.uid.substring(0, 6)}...(${s.email})").join(", ")}',
    );
    return accounts;
  }

  Future<UserSession?> getActiveAccount() async {
    final activeId = await storage.getActiveAccountId();
    if (activeId == null || activeId.isEmpty) return null;
    final sessions = await storage.getSessions();
    for (final s in sessions) {
      if (s.uid == activeId) return s;
    }
    return sessions.isNotEmpty ? sessions.first : null;
  }

  // ── Switch ────────────────────────────────────────────────────────────

  Future<bool> switchAccount(String uid) async {
    dev.log('[multi-account] switchAccount START target=$uid');
    final creds = await storage.getCredentials(uid);
    if (creds == null) {
      dev.log('[multi-account] switchAccount FAILED: no credentials for $uid');
      return false;
    }

    final previousActiveId = await storage.getActiveAccountId();
    final previousUserUid = firebaseAuth.currentUser?.uid;

    if (previousUserUid == uid) {
      final persisted = await storage.setActiveAccountId(uid);
      if (!persisted) {
        dev.log(
          '[multi-account] switchAccount FAILED: could not persist active id '
          'for already-active user',
        );
        return false;
      }
      dev.log('[multi-account] switchAccount NOOP (already active) for $uid');
      return true;
    }

    final activeSaved = await storage.setActiveAccountId(uid);
    if (!activeSaved) {
      dev.log('[multi-account] switchAccount FAILED: active id persist failed');
      return false;
    }

    try {
      await firebaseAuth.signOut().timeout(const Duration(seconds: 12));
      final credential = await firebaseAuth
          .signInWithEmailAndPassword(
            email: creds['email']!,
            password: creds['password']!,
          )
          .timeout(const Duration(seconds: 20));
      if (credential.user?.uid != uid) {
        throw StateError('Switched into unexpected account');
      }

      final sessions = await storage.getSessions();
      final idx = sessions.indexWhere((s) => s.uid == uid);
      if (idx != -1) {
        sessions[idx] = sessions[idx].copyWith(lastLogin: DateTime.now());
        await storage.saveSessions(sessions);
      }
      dev.log('[multi-account] switchAccount SUCCESS for $uid');
      return true;
    } catch (e) {
      await storage.setActiveAccountId(previousActiveId ?? '');
      dev.log('[multi-account] switchAccount FAILED: $e');
      return false;
    }
  }

  // ── Remove ────────────────────────────────────────────────────────────

  Future<void> removeAccount(String uid) async {
    final sessions = await storage.getSessions();
    sessions.removeWhere((s) => s.uid == uid);
    await storage.saveSessions(sessions);
    await storage.removeCredentials(uid);

    final activeId = await storage.getActiveAccountId();
    if (activeId == uid) {
      final nextId = sessions.isNotEmpty ? sessions.first.uid : '';
      await storage.setActiveAccountId(nextId);
    }
  }

  Future<UserSession?> nextAccountAfterRemoval(String uid) async {
    final sessions = await storage.getSessions();
    final remaining = sessions.where((s) => s.uid != uid).toList();
    return remaining.isNotEmpty ? remaining.first : null;
  }

  Future<void> clearLocalAuthArtifacts() async {
    await storage.clearAll();
  }
}
