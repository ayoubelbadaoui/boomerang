import 'dart:async';
import 'dart:developer' as dev;

import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/feed/application/feed_controller.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/core/notifications/push_notifications_service.dart';
import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Application-layer controller that owns the account-switching flow.
///
/// Operates on a [ProviderContainer] captured while the calling widget is
/// still mounted, so it remains valid after bottom sheets are dismissed.
class AccountSwitchController {
  AccountSwitchController(this._container);
  final ProviderContainer _container;
  int _switchGeneration = 0;

  Future<void> _waitForTargetAuthSession(String targetUid) async {
    final auth = _container.read(firebaseAuthProvider);
    if (auth.currentUser?.uid != targetUid) {
      await auth
          .authStateChanges()
          .firstWhere((u) => u?.uid == targetUid)
          .timeout(const Duration(seconds: 10));
    }
    await auth.currentUser?.getIdToken(true);
  }

  /// Whether stored credentials exist for [uid].
  Future<bool> hasCredentials(String uid) async {
    final storage = _container.read(sessionStorageProvider);
    return await storage.getCredentials(uid) != null;
  }

  /// Ensures the current Firebase user is persisted in session storage
  /// and that its display name / avatar are up-to-date.
  Future<void> ensureCurrentAccountStored() async {
    try {
      final auth = _container.read(firebaseAuthProvider);
      final user = auth.currentUser;
      dev.log('[multi-account] ensureStored: currentUser=${user?.uid}');
      if (user == null) return;

      final manager = _container.read(multiAccountManagerProvider);
      final accounts = await manager.getAccounts();
      final profileCandidate =
          _container.read(currentUserProfileProvider).value;
      final profile =
          profileCandidate != null && profileCandidate.uid == user.uid
              ? profileCandidate
              : null;

      if (accounts.any((a) => a.uid == user.uid)) {
        if (profile != null) {
          final displayName =
              profile.fullName.isNotEmpty ? profile.fullName : profile.nickname;
          await manager.updateAccountProfile(
            user.uid,
            displayName: displayName,
            photoUrl: profile.avatarUrl,
          );
          _container.invalidate(storedAccountsProvider);
        }
        return;
      }

      dev.log('[multi-account] ensureStored: ADDING ${user.uid}');
      await manager.addAccount(
        UserSession(
          uid: user.uid,
          email: profile?.email ?? user.email ?? '',
          displayName:
              profile != null
                  ? (profile.fullName.isNotEmpty
                      ? profile.fullName
                      : profile.nickname)
                  : (user.displayName ?? ''),
          photoUrl: profile?.avatarUrl ?? user.photoURL,
          lastLogin: DateTime.now(),
        ),
      );
      _container.invalidate(storedAccountsProvider);
    } catch (e) {
      dev.log('[multi-account] ensureStored FAILED: $e');
    }
  }

  /// Unified switch flow for both the stored-credentials and password paths.
  ///
  /// If [password] is provided (re-login case), credentials are persisted
  /// first so [MultiAccountManager.switchAccount] can sign in.
  /// Returns `true` on success.
  Future<bool> switchTo(UserSession target, {String? password}) async {
    final switchId = ++_switchGeneration;
    _container.read(isSwitchingAccountProvider.notifier).state = true;
    try {
      final manager = _container.read(multiAccountManagerProvider);
      final storage = _container.read(sessionStorageProvider);
      final firestore = _container.read(firestoreProvider);

      final currentUid = _container.read(firebaseAuthProvider).currentUser?.uid;
      final currentProfile = _container.read(currentUserProfileProvider).value;

      // Snapshot outgoing user's profile so the switcher shows correct data
      if (currentUid != null &&
          currentProfile != null &&
          currentProfile.uid == currentUid) {
        await manager.updateAccountProfile(
          currentUid,
          displayName:
              currentProfile.fullName.isNotEmpty
                  ? currentProfile.fullName
                  : currentProfile.nickname,
          photoUrl: currentProfile.avatarUrl,
        );
      }

      // Remove push token for the outgoing user
      if (currentUid != null && currentUid.isNotEmpty) {
        try {
          await removeCurrentDeviceTokenForUser(firestore, currentUid);
        } catch (_) {}
      }

      // For the password path, save credentials before switching
      if (password != null) {
        final credsSaved = await storage.saveCredentials(
          target.uid,
          target.email,
          password,
        );
        if (!credsSaved) {
          dev.log(
            '[multi-account] switchTo FAILED: could not persist password',
          );
          return false;
        }
      }

      // signOut → signIn via stored credentials
      final success = await manager.switchAccount(target.uid);
      dev.log('[multi-account] switchTo result=$success uid=${target.uid}');

      if (switchId != _switchGeneration) {
        // A newer switch already started; ignore this stale completion.
        return false;
      }

      if (success) {
        try {
          await _waitForTargetAuthSession(target.uid);
        } on TimeoutException {
          dev.log(
            '[multi-account] switchTo FAILED: auth state did not settle '
            'for ${target.uid}',
          );
          return false;
        } on FirebaseAuthException catch (e, st) {
          dev.log(
            '[multi-account] switchTo FAILED: token refresh failed',
            error: e,
            stackTrace: st,
          );
          return false;
        }
        invalidateUserScopedProviders(_container);
        _container.invalidate(feedControllerProvider(FeedSurface.home));
        _container.invalidate(feedControllerProvider(FeedSurface.discovery));
        _container.invalidate(profileControllerProvider);
        _container.invalidate(userBoomerangsControllerProvider);
        _container.invalidate(storedAccountsProvider);
      }

      return success;
    } catch (e, st) {
      dev.log('[multi-account] switchTo FAILED: $e', error: e, stackTrace: st);
      return false;
    } finally {
      if (switchId == _switchGeneration) {
        _container.read(isSwitchingAccountProvider.notifier).state = false;
      }
    }
  }
}
