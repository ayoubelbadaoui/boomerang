import 'dart:developer' as dev;
import 'dart:io';

import 'package:boomerang/core/auth/session_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

class InstallSessionGuardResult {
  const InstallSessionGuardResult({
    required this.wasFreshInstall,
    required this.purgedStaleCredentials,
  });

  final bool wasFreshInstall;
  final bool purgedStaleCredentials;
}

/// Detects a fresh install using app-local file storage and clears stale
/// auth state that may be restored by platform keystore/keychain persistence.
class InstallSessionGuard {
  InstallSessionGuard({
    FirebaseAuth? firebaseAuth,
    SessionStorage? sessionStorage,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _sessionStorage = sessionStorage ?? SessionStorage();

  final FirebaseAuth _firebaseAuth;
  final SessionStorage _sessionStorage;

  Future<InstallSessionGuardResult> enforce() async {
    final markerFile = await _markerFile();
    final markerExists = markerFile.existsSync();

    if (markerExists) {
      return const InstallSessionGuardResult(
        wasFreshInstall: false,
        purgedStaleCredentials: false,
      );
    }

    final hasRestoredFirebaseUser = _firebaseAuth.currentUser != null;
    final activeAccountId = await _sessionStorage.getActiveAccountId();
    final storedAccounts = await _sessionStorage.getSessions();
    final hasLocalSessionData =
        (activeAccountId?.isNotEmpty ?? false) || storedAccounts.isNotEmpty;

    var purgedStaleCredentials = false;
    if (hasRestoredFirebaseUser || hasLocalSessionData) {
      purgedStaleCredentials = true;
      await _purgeAuthArtifacts();
      dev.log(
        '[auth-install] fresh-install stale session purged '
        '(firebaseUser=$hasRestoredFirebaseUser, '
        'localSessionData=$hasLocalSessionData)',
      );
    } else {
      dev.log('[auth-install] fresh-install detected without stale session');
    }

    await _writeInstallMarker(markerFile);
    return InstallSessionGuardResult(
      wasFreshInstall: true,
      purgedStaleCredentials: purgedStaleCredentials,
    );
  }

  Future<File> _markerFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/install.marker');
  }

  Future<void> _writeInstallMarker(File markerFile) async {
    await markerFile.writeAsString(
      DateTime.now().toIso8601String(),
      flush: true,
    );
  }

  Future<void> _purgeAuthArtifacts() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      dev.log('[auth-install] firebase signOut during purge failed: $e');
    }
    try {
      await _sessionStorage.clearAll();
    } catch (e) {
      dev.log('[auth-install] local session purge failed: $e');
    }
  }
}
