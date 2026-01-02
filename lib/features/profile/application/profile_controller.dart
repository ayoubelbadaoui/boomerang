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
    String? phone,
    String? address,
    String? bio,
    String? instagram,
    String? facebook,
    String? twitter,
  }) async {
    final repo = ref.read(userProfileRepoProvider);
    await repo.updateCurrentUserProfile(
      fullName: fullName,
      nickname: nickname,
      avatarUrl: avatarUrl,
      phone: phone,
      address: address,
      bio: bio,
      instagram: instagram,
      facebook: facebook,
      twitter: twitter,
    );
  }
}
