import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'user_session.dart';

/// Persists multi-account session data using app-private file storage.
/// Uses [path_provider] (already a dependency) — no extra native plugins.
/// All reads/writes are fully exception-safe.
class SessionStorage {
  File? _sessionsFile;
  File? _activeFile;
  Directory? _credDir;

  Future<Directory> _baseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory('${dir.path}/multi_account');
    if (!sub.existsSync()) await sub.create(recursive: true);
    return sub;
  }

  Future<File> _getSessionsFile() async {
    if (_sessionsFile != null) return _sessionsFile!;
    final dir = await _baseDir();
    _sessionsFile = File('${dir.path}/sessions.json');
    return _sessionsFile!;
  }

  Future<File> _getActiveFile() async {
    if (_activeFile != null) return _activeFile!;
    final dir = await _baseDir();
    _activeFile = File('${dir.path}/active_uid.txt');
    return _activeFile!;
  }

  Future<File> _credFile(String uid) async {
    final dir = await _baseDir();
    _credDir ??= Directory('${dir.path}/creds');
    if (!_credDir!.existsSync()) await _credDir!.create(recursive: true);
    return File('${_credDir!.path}/$uid.json');
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  Future<List<UserSession>> getSessions() async {
    try {
      final file = await _getSessionsFile();
      if (!file.existsSync()) {
        dev.log('[multi-account] storage.getSessions: file does not exist');
        return [];
      }
      final raw = await file.readAsString();
      if (raw.isEmpty) return [];
      final list = UserSession.decodeList(raw);
      dev.log(
        '[multi-account] storage.getSessions: ${list.length} sessions: '
        '${list.map((s) => "${s.uid.substring(0, 6)}...(${s.email})").join(", ")}',
      );
      return list;
    } catch (e) {
      dev.log('[multi-account] storage.getSessions FAILED: $e');
      return [];
    }
  }

  Future<bool> saveSessions(List<UserSession> sessions) async {
    try {
      final file = await _getSessionsFile();
      final encoded = UserSession.encodeList(sessions);
      await file.writeAsString(encoded, flush: true);
      dev.log(
        '[multi-account] storage.saveSessions OK: ${sessions.length} sessions',
      );
      return true;
    } catch (e) {
      dev.log('[multi-account] storage.saveSessions FAILED: $e');
      return false;
    }
  }

  // ── Active account ────────────────────────────────────────────────────

  Future<String?> getActiveAccountId() async {
    try {
      final file = await _getActiveFile();
      if (!file.existsSync()) return null;
      final id = await file.readAsString();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> setActiveAccountId(String uid) async {
    try {
      final file = await _getActiveFile();
      await file.writeAsString(uid, flush: true);
    } catch (e) {
      dev.log('[multi-account] storage.setActiveAccountId FAILED: $e');
    }
  }

  // ── Credentials ───────────────────────────────────────────────────────

  Future<void> saveCredentials(
    String uid,
    String email,
    String password,
  ) async {
    try {
      final file = await _credFile(uid);
      final payload = jsonEncode({'email': email, 'password': password});
      await file.writeAsString(payload, flush: true);
      dev.log('[multi-account] storage.saveCredentials OK for $email');
    } catch (e) {
      dev.log('[multi-account] storage.saveCredentials FAILED: $e');
    }
  }

  Future<Map<String, String>?> getCredentials(String uid) async {
    try {
      final file = await _credFile(uid);
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      dev.log('[multi-account] storage.getCredentials($uid) found');
      return {
        'email': map['email'] as String,
        'password': map['password'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> removeCredentials(String uid) async {
    try {
      final file = await _credFile(uid);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    try {
      final dir = await _baseDir();
      if (dir.existsSync()) await dir.delete(recursive: true);
      _sessionsFile = null;
      _activeFile = null;
      _credDir = null;
    } catch (_) {}
  }
}
