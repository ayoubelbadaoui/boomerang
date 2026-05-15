import 'dart:async';
import 'dart:io';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(
      ProfileController.new,
    );

class ProfileController extends AsyncNotifier<UserProfile?> {
  String? _activeUid;

  @override
  Future<UserProfile?> build() async {
    // Ensure there is always at least a minimal profile document
    final repo = ref.read(userProfileRepoProvider);
    await repo.ensureBasicProfileIfMissing();

    _activeUid = ref.read(firebaseAuthProvider).currentUser?.uid;

    // Clear stale profile state immediately when auth user changes.
    ref.listen(authStateProvider, (previous, next) {
      final nextUid = next.asData?.value?.uid;
      if (nextUid == _activeUid) return;
      _activeUid = nextUid;
      state = const AsyncLoading();
      ref.invalidate(userBoomerangsControllerProvider);
    });

    // Keep state in sync with the Firestore stream
    ref.listen(currentUserProfileProvider, (previous, next) {
      next.when(
        data: (value) {
          final authUid = ref.read(firebaseAuthProvider).currentUser?.uid;
          if (value != null && authUid != null && value.uid != authUid) {
            // Ignore late emissions from a previous account session.
            return;
          }
          state = AsyncData(value);
        },
        loading: () => state = const AsyncLoading(),
        error: (error, stackTrace) => state = AsyncError(error, stackTrace),
      );
    });

    // Resolve initial value
    return await ref.read(currentUserProfileProvider.future);
  }

  Future<String> uploadAvatar(File file) async {
    final repo = ref.read(userProfileRepoProvider);
    return repo.uploadAvatar(file);
  }

  /// Live availability check for the username/nickname edit UI. Matches
  /// the signup-time semantics: returns true when the candidate is
  /// unclaimed or already owned by the current user.
  Future<bool> isUsernameAvailable(String candidate) async {
    final repo = ref.read(userProfileRepoProvider);
    return repo.isUsernameAvailable(candidate);
  }

  Future<void> updateProfile({
    String? fullName,
    String? nickname,
    String? avatarUrl,
    String? bio,
  }) async {
    final repo = ref.read(userProfileRepoProvider);
    await repo.updateCurrentUserProfile(
      fullName: fullName,
      nickname: nickname,
      avatarUrl: avatarUrl,
      bio: bio,
    );

    // Keep multi-account session data in sync for the switcher UI
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid != null && (fullName != null || avatarUrl != null)) {
      await ref.read(multiAccountManagerProvider).updateAccountProfile(
            uid,
            displayName: fullName,
            photoUrl: avatarUrl,
          );
    }
  }
}
