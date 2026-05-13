import 'dart:async';
import 'dart:io';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(
      ProfileController.new,
    );

class ProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    // Ensure there is always at least a minimal profile document
    final repo = ref.read(userProfileRepoProvider);
    await repo.ensureBasicProfileIfMissing();

    // Keep state in sync with the Firestore stream
    ref.listen(currentUserProfileProvider, (previous, next) {
      next.when(
        data: (value) => state = AsyncData(value),
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
