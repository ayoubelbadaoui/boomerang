import 'package:boomerang/features/auth/application/auth_controller.dart';
import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:boomerang/features/auth/infrastructure/firebase_auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
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
import 'package:boomerang/features/profile/infrastructure/user_search_repo.dart';
import 'package:boomerang/features/feed/infrastructure/hashtag_repo.dart';
import 'package:boomerang/features/profile/infrastructure/saved_repo.dart';
import 'package:boomerang/core/auth/session_storage.dart';
import 'package:boomerang/core/auth/multi_account_manager.dart';
import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
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

final sessionStorageProvider = Provider<SessionStorage>(
  (_) => SessionStorage(),
);

final multiAccountManagerProvider = Provider<MultiAccountManager>((ref) {
  return MultiAccountManager(
    storage: ref.watch(sessionStorageProvider),
    firebaseAuth: ref.watch(firebaseAuthProvider),
  );
});

/// All stored account sessions (refreshable).
final storedAccountsProvider = FutureProvider<List<UserSession>>((ref) {
  return ref.watch(multiAccountManagerProvider).getAccounts();
});

/// Set to `true` while an account switch is in progress so auth guards
/// (HomeShell, router redirect) don't react to the transient sign-out.
final isSwitchingAccountProvider = StateProvider<bool>((ref) => false);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final repo = ref.watch(authRepoProvider);
    final manager = ref.watch(multiAccountManagerProvider);
    return AuthController(repo, manager);
  },
);

/// Checks whether the current authenticated user has a profile document
/// at `users/{uid}` in Firestore. Returns false if no user is authenticated.
final userProfileExistsProvider = FutureProvider<bool>((ref) async {
  // Track auth state changes so this provider refreshes on sign-in/out
  final authState = ref.watch(authStateProvider);
  final user = authState.asData?.value;
  if (user == null) return false;
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('users').doc(user.uid).get();
  return doc.exists;
});

/// Checks whether the user profile is fully completed with required fields
/// gender, birthday, and phone under `users/{uid}`.
final userProfileCompleteProvider = FutureProvider<bool>((ref) async {
  // Track auth state changes so this provider refreshes on sign-in/out
  final authState = ref.watch(authStateProvider);
  final user = authState.asData?.value;
  if (user == null) return false;
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('users').doc(user.uid).get();
  if (!doc.exists) return false;
  final data = doc.data();
  if (data == null) return false;
  return (data['gender'] != null &&
      data['birthday'] != null &&
      data['phone'] != null);
});

/// Does the current user have a valid nickname persisted?
final userHasNicknameProvider = FutureProvider<bool>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.asData?.value;
  if (user == null) return false;
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('users').doc(user.uid).get();
  if (!doc.exists) return false;
  final data = doc.data();
  if (data == null) return false;
  final nickname = (data['nickname'] ?? data['username'] ?? '') as String;
  final nicknameLower = (data['nicknameLower'] ?? '') as String;
  final ok = nickname.trim().isNotEmpty &&
      nicknameLower.trim().isNotEmpty &&
      nicknameLower == nicknameLower.toLowerCase();
  if (!ok) {
    debugPrint('userHasNicknameProvider: missing/invalid nickname for ${user.uid}');
  }
  return ok;
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

/// Stream of post ids liked by the current user.
/// Reads from users/{uid}/likes subcollection instead of scanning all boomerangs.
final likedPostIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return const Stream.empty();
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('users')
      .doc(user.uid)
      .collection('likes')
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toSet())
      .handleError((e, st) {
        debugPrint('likedPostIdsProvider error: $e');
      });
});

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) async* {
  final auth = ref.watch(firebaseAuthProvider);
  await for (final u in auth.authStateChanges()) {
    if (u == null) {
      yield null;
      continue;
    }
    final fs = ref.read(firestoreProvider);
    try {
      await for (final snap in fs.collection('users').doc(u.uid).snapshots()) {
        if (!snap.exists || snap.data() == null) {
          yield null;
        } else {
          yield UserProfile.fromMap(snap.id, snap.data()!);
        }
      }
    } catch (e) {
      // Firestore listener may throw permission-denied after sign-out
      yield null;
    }
  }
});

/// Stream a user profile by arbitrary user id
final userProfileByIdProvider = StreamProvider.family<UserProfile?, String>((
  ref,
  uid,
) async* {
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

/// Real-time stream of notification docs for the given user (stable per uid).
final notificationsStreamProvider =
    StreamProvider.family<QuerySnapshot<Map<String, dynamic>>, String>((ref, uid) {
  if (uid.isEmpty) return const Stream.empty();
  return ref.watch(notificationsRepoProvider).watch(uid).handleError((e, st) {
    debugPrint('notificationsStreamProvider error: $e');
  });
});

final outgoingFollowRequestProvider =
    StreamProvider.family<FollowRequest?, String>((ref, targetId) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null) return const Stream.empty();
  return ref
      .watch(followRepoProvider)
      .watchRequest(receiverId: targetId, senderId: me.uid)
      .handleError((e, st) {});
});

final incomingFollowRequestProvider =
    StreamProvider.family<FollowRequest?, String>((ref, senderId) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null) return const Stream.empty();
  return ref
      .watch(followRepoProvider)
      .watchRequest(receiverId: me.uid, senderId: senderId)
      .handleError((e, st) {});
});

final isFollowingStreamProvider =
    StreamProvider.family<bool, String>((ref, targetId) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null || me.uid == targetId) return const Stream.empty();
  return ref.watch(followRepoProvider).watchIsFollowing(targetId)
      .handleError((e, st) {});
});

/// Whether [userId] follows the current user.
final isFollowedByProvider =
    StreamProvider.family<bool, String>((ref, userId) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null || me.uid == userId) return Stream.value(false);
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('followers')
      .doc(me.uid)
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((snap) => snap.exists)
      .handleError((e, st) {});
});

/// Unread notifications count for current user.
final unreadCountProvider =
    StreamProvider.family<int, String>((ref, uid) async* {
  try {
    yield* ref.watch(notificationsRepoProvider).watchUnreadCount(uid);
  } catch (_) {
    yield 0;
  }
});

final savedRepoProvider = Provider<SavedRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return SavedRepo(fs);
});

final userSearchRepoProvider = Provider<UserSearchRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return UserSearchRepo(fs);
});

final hashtagRepoProvider = Provider<HashtagRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return HashtagRepo(fs);
});

final followRepoProvider = Provider<FollowRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return FollowRepo(fs, auth);
});

/// Live set of UIDs the current user follows (for feed filtering).
final followingIdsProvider = StreamProvider<Set<String>>((ref) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null) return const Stream.empty();
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('following')
      .doc(me.uid)
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toSet())
      .handleError((e, st) {});
});

/// Counts fetched once per tab-open / pull-to-refresh.
/// Call ref.invalidate(…) to re-fetch.
final followersCountProvider = FutureProvider.family<int, String>((ref, uid) async {
  final fs = ref.read(firestoreProvider);
  final snap = await fs.collection('users').doc(uid).get();
  return (snap.data()?['followersCount'] ?? 0) as int;
});

final followingCountProvider = FutureProvider.family<int, String>((ref, uid) async {
  final fs = ref.read(firestoreProvider);
  final snap = await fs.collection('users').doc(uid).get();
  return (snap.data()?['followingCount'] ?? 0) as int;
});

final userBoomerangsCountProvider = FutureProvider.family<int, String>((ref, uid) async {
  final fs = ref.read(firestoreProvider);
  final snap = await fs.collection('users').doc(uid).get();
  return (snap.data()?['boomerangsCount'] ?? 0) as int;
});

final userTotalLikesProvider = FutureProvider.family<int, String>((ref, uid) async {
  final fs = ref.read(firestoreProvider);
  final snap = await fs.collection('users').doc(uid).get();
  return (snap.data()?['totalLikes'] ?? 0) as int;
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

/// Guard: keep the denormalised `ownerIsPrivate` flag on every boomerang in
/// sync with the current user's `isPrivate` setting. Without this, posts
/// created before a privacy toggle would keep leaking through the discover
/// and hashtag feeds (which filter server-side on this flag). Idempotent —
/// only writes documents whose flag actually drifted.
final privacyBackfillGuardProvider = Provider<void>((ref) {
  final lastSynced = <String, bool>{};
  ref.listen<AsyncValue<UserProfile?>>(currentUserProfileProvider,
      (prev, next) {
    final profile = next.asData?.value;
    if (profile == null) return;
    if (lastSynced[profile.uid] == profile.isPrivate) return;
    lastSynced[profile.uid] = profile.isPrivate;
    // Fire-and-forget: this is a best-effort consistency backfill.
    ref
        .read(boomerangRepoProvider)
        .syncOwnerPrivacy(uid: profile.uid, isPrivate: profile.isPrivate)
        .catchError((_) {});
  });
});

/// Call on logout (and optionally after login) so the UI never shows the previous user.
/// Invalidates all providers that cache or stream current-user data.
void invalidateUserScopedProviders(ProviderContainer container) {
  container.invalidate(userHasNicknameProvider);
  container.invalidate(userProfileExistsProvider);
  container.invalidate(userProfileCompleteProvider);
  container.invalidate(currentUserProfileProvider);
  container.invalidate(likedPostIdsProvider);
  container.invalidate(outgoingFollowRequestProvider);
  container.invalidate(incomingFollowRequestProvider);
  container.invalidate(isFollowingStreamProvider);
  container.invalidate(unreadCountProvider);
  container.invalidate(blockedUsersProvider);
  container.invalidate(followingIdsProvider);
}
