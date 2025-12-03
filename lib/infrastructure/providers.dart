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
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';
import 'package:boomerang/features/feed/infrastructure/notifications_repo.dart';
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
  if (doc.exists) return true;
  // Create a minimal profile document so setup flow can complete it
  final repo = ref.read(userProfileRepoProvider);
  await repo.ensureBasicProfileIfMissing();
  return true;
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

/// Stream a user profile by arbitrary user id
final userProfileByIdProvider =
    StreamProvider.family<UserProfile?, String>((ref, uid) async* {
  final fs = ref.watch(firestoreProvider);
  await for (final snap in fs.collection('users').doc(uid).snapshots()) {
    if (!snap.exists || snap.data() == null) {
      yield null;
    } else {
      yield UserProfile.fromMap(snap.id, snap.data()!);
    }
  }
});
final commentsRepoProvider = Provider<CommentsRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return CommentsRepo(fs);
});

final notificationsRepoProvider = Provider<NotificationsRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return NotificationsRepo(fs);
});

final followRepoProvider = Provider<FollowRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return FollowRepo(fs, auth);
});

/// Live count providers for followers/following
final followersCountProvider = StreamProvider.family<int, String>((ref, uid) {
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('followers')
      .doc(uid)
      .collection('users')
      .snapshots()
      .map((snap) => snap.size);
});

final followingCountProvider = StreamProvider.family<int, String>((ref, uid) {
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('following')
      .doc(uid)
      .collection('users')
      .snapshots()
      .map((snap) => snap.size);
});

/// Number of boomerangs created by a user
final userBoomerangsCountProvider = StreamProvider.family<int, String>((
  ref,
  uid,
) {
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('boomerangs')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.size);
});

/// Total likes across a user's boomerangs
final userTotalLikesProvider = StreamProvider.family<int, String>((ref, uid) {
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('boomerangs')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        int total = 0;
        for (final d in snap.docs) {
          final data = d.data();
          final likes = (data['likes'] ?? 0);
          if (likes is int) total += likes;
        }
        return total;
      });
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

/// Guard: if a user is authenticated but their `users/{uid}` doc does not exist,
/// log them out so the app shows onboarding. This runs globally once activated.
final profileGuardProvider = Provider<void>((ref) {
  ref.listen(currentUserProfileProvider, (prev, next) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user != null && next.asData != null && next.asData!.value == null) {
      // No profile document; force sign out
      await ref.read(authControllerProvider.notifier).logout();
    }
  });
});
