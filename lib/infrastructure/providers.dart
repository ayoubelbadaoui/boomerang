import 'package:boomerang/features/auth/application/auth_controller.dart';
import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:boomerang/features/auth/infrastructure/firebase_auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:boomerang/features/profile/infrastructure/user_profile_repo.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_repo.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/feed/infrastructure/comments_repo.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_service.dart';
// import 'package:path_provider/path_provider.dart';
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

/// Checks whether the current authenticated user has a profile document
/// at `users/{uid}` in Firestore. Returns false if no user is authenticated.
final userProfileExistsProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) return false;
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('users').doc(user.uid).get();
  return doc.exists;
});

/// Checks whether the user profile is fully completed with required fields
/// birthday, phone, and address under `users/{uid}`.
final userProfileCompleteProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) return false;
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('users').doc(user.uid).get();
  if (!doc.exists) return false;
  final data = doc.data();
  if (data == null) return false;
  return (data['gender'] != null &&
      data['birthday'] != null &&
      data['phone'] != null &&
      data['address'] != null);
});

final userProfileRepoProvider = Provider<UserProfileRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final storage = ref.watch(storageProvider);
  return UserProfileRepo(fs, auth, storage);
});

final boomerangRepoProvider = Provider<BoomerangRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return BoomerangRepo(fs);
});

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) async* {
  final auth = ref.watch(firebaseAuthProvider);
  // bridge auth changes
  await for (final u in auth.authStateChanges()) {
    if (u == null) {
      yield null;
      continue;
    }
    final fs = ref.read(firestoreProvider);
    await for (final snap in fs.collection('users').doc(u.uid).snapshots()) {
      if (!snap.exists || snap.data() == null) {
        yield null;
      } else {
        yield UserProfile.fromMap(snap.id, snap.data()!);
      }
    }
  }
});

final commentsRepoProvider = Provider<CommentsRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return CommentsRepo(fs);
});

final boomerangProcessorProvider = Provider<BoomerangProcessor>((ref) {
  return const BoomerangProcessor();
});

final boomerangServiceProvider = Provider<BoomerangService>((ref) {
  final fs = ref.watch(firestoreProvider);
  final storage = ref.watch(storageProvider);
  final processor = ref.watch(boomerangProcessorProvider);
  final repo = ref.watch(boomerangRepoProvider);
  return BoomerangService(fs, storage, processor, repo);
});
