import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';

import 'session_storage.dart';
import 'user_session.dart';

/// Orchestrates multi-account storage, switching, and removal.
class MultiAccountManager {
  MultiAccountManager({required this.storage, required this.firebaseAuth});

  final SessionStorage storage;
  final FirebaseAuth firebaseAuth;

  String _normalizedEmail(String email) => email.trim().toLowerCase();

  List<UserSession> _dedupeSessions(List<UserSession> sessions) {
    final seenUids = <String>{};
    final seenEmails = <String>{};
    final deduped = <UserSession>[];

    // Keep most recent entries first when de-duplicating.
    final ordered = [...sessions]
      ..sort((a, b) => b.lastLogin.compareTo(a.lastLogin));

    for (final session in ordered) {
      final normalizedEmail = _normalizedEmail(session.email);
      final hasEmail = normalizedEmail.isNotEmpty;
      if (seenUids.contains(session.uid)) continue;
      if (hasEmail && seenEmails.contains(normalizedEmail)) continue;
      seenUids.add(session.uid);
      if (hasEmail) seenEmails.add(normalizedEmail);
      deduped.add(session);
    }
    return deduped;
  }

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
    final normalizedIncomingEmail = _normalizedEmail(session.email);
    sessions.removeWhere((s) {
      if (s.uid == session.uid) return true;
      final existingEmail = _normalizedEmail(s.email);
      return normalizedIncomingEmail.isNotEmpty &&
          existingEmail == normalizedIncomingEmail;
    });
    sessions.add(session);
    final merged = _dedupeSessions(sessions);

    dev.log(
      '[multi-account] addAccount: after merge count=${merged.length} '
      '(was $hadBefore) uids=${merged.map((s) => s.uid.substring(0, 6)).join(",")}',
    );

    final sessionsSaved = await storage.saveSessions(merged);
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
    final deduped = _dedupeSessions(accounts);
    if (deduped.length != accounts.length) {
      await storage.saveSessions(deduped);
    }
    dev.log(
      '[multi-account] getAccounts: ${deduped.length} accounts '
      '${deduped.map((s) => "${s.uid.substring(0, 6)}...(${s.email})").join(", ")}',
    );
    return deduped;
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
