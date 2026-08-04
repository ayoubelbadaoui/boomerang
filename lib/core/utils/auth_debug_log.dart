import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Debug logging for auth failures. Helps distinguish wrong credentials
/// from Firebase config / project mismatches.
class AuthDebugLog {
  AuthDebugLog._();

  static void logFirebaseContext() {
    try {
      final options = Firebase.app().options;
      dev.log(
        'Firebase context: projectId=${options.projectId} '
        'appId=${options.appId} '
        'authDomain=${options.authDomain ?? 'n/a'} '
        'apiKey=${_maskApiKey(options.apiKey)}',
        name: 'Auth',
      );
    } catch (e) {
      dev.log('Firebase context unavailable: $e', name: 'Auth');
    }
  }

  static String classifyFailure(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-credential':
        case 'invalid-email':
          return 'likely_wrong_credentials';
        case 'invalid-api-key':
        case 'app-not-authorized':
        case 'project-not-found':
        case 'operation-not-allowed':
          return 'likely_firebase_config';
        case 'network-request-failed':
          return 'network';
        case 'too-many-requests':
          return 'rate_limited';
        default:
          return 'auth_error';
      }
    }
    if (error is FirebaseException) {
      return 'firebase_service_error';
    }
    if (error is StateError) {
      return 'app_state_error';
    }
    return 'unknown';
  }

  static void authFailed({
    required String flow,
    required Object error,
    StackTrace? stackTrace,
    String? identifier,
    String? resolvedEmail,
    String? step,
  }) {
    logFirebaseContext();

    final classification = classifyFailure(error);
    final buffer =
        StringBuffer()
          ..writeln('$flow FAILED')
          ..writeln('  step: ${step ?? 'unknown'}')
          ..writeln('  classification: $classification');

    if (identifier != null) {
      buffer.writeln('  identifier: $identifier');
    }
    if (resolvedEmail != null) {
      buffer.writeln('  resolvedEmail: $resolvedEmail');
    }

    if (error is FirebaseAuthException) {
      buffer
        ..writeln('  firebaseAuth.code: ${error.code}')
        ..writeln('  firebaseAuth.message: ${error.message ?? 'n/a'}');
    } else if (error is FirebaseException) {
      buffer
        ..writeln('  firebase.code: ${error.code}')
        ..writeln('  firebase.message: ${error.message ?? 'n/a'}');
    } else {
      buffer.writeln('  error: $error');
    }

    switch (classification) {
      case 'likely_wrong_credentials':
        buffer.writeln(
          '  hint: Wrong email/username or password for this Firebase project.',
        );
      case 'likely_firebase_config':
        buffer.writeln(
          '  hint: Check firebase_options.dart matches your Firebase console '
          'project and that Email/Password sign-in is enabled.',
        );
      case 'network':
        buffer.writeln('  hint: Device may be offline or blocking Firebase.');
      case 'firebase_service_error':
        buffer.writeln(
          '  hint: Firestore or another Firebase service failed during sign-in.',
        );
      default:
        break;
    }

    dev.log(
      buffer.toString(),
      name: 'Auth',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String _maskApiKey(String? key) {
    if (key == null || key.length <= 8) return 'n/a';
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }
}
