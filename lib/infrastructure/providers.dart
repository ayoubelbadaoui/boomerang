import 'package:boomerang/features/auth/application/auth_controller.dart';
import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:boomerang/features/auth/infrastructure/firebase_auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
// import 'package:firebase_core/firebase_core.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final storageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

/// Stream of Firebase [User?]
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

final authRepoProvider = Provider<AuthRepo>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return FirebaseAuthRepo(auth);
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final repo = ref.watch(authRepoProvider);
    return AuthController(repo);
  },
);
