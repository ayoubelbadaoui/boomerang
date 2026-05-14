import 'dart:async';

import 'package:boomerang/features/profile/domain/app_settings.dart';
import 'package:boomerang/features/profile/infrastructure/settings_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsRepoProvider = Provider<SettingsRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return SettingsRepo(fs, auth);
});

final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(firebaseAuthProvider).currentUser?.uid;
});

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

enum PrivacyUpdateStatus { idle, updating, success, failure }

class PrivacyUpdateState {
  const PrivacyUpdateState({
    required this.status,
    this.targetValue,
    this.message,
  });

  const PrivacyUpdateState.idle() : this(status: PrivacyUpdateStatus.idle);

  final PrivacyUpdateStatus status;
  final bool? targetValue;
  final String? message;

  bool get isUpdating => status == PrivacyUpdateStatus.updating;
}

final privacyUpdateStateProvider = StateProvider<PrivacyUpdateState>(
  (ref) => const PrivacyUpdateState.idle(),
);

class SettingsController extends AsyncNotifier<AppSettings> {
  bool _privacyUpdateInFlight = false;
  bool? _pendingPrivacyTarget;

  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepoProvider);
    final sub = repo.watch().listen((value) {
      final pendingPrivacyTarget = _pendingPrivacyTarget;
      if (pendingPrivacyTarget != null &&
          value.privateAccount != pendingPrivacyTarget) {
        // Keep optimistic privacy state until remote catches up.
        state = AsyncData(value.copyWith(privateAccount: pendingPrivacyTarget));
        return;
      }
      if (pendingPrivacyTarget != null &&
          value.privateAccount == pendingPrivacyTarget) {
        _pendingPrivacyTarget = null;
        if (ref.read(privacyUpdateStateProvider).status ==
            PrivacyUpdateStatus.success) {
          ref.read(privacyUpdateStateProvider.notifier).state =
              const PrivacyUpdateState.idle();
        }
      }
      state = AsyncData(value);
    }, onError: (_) {});
    ref.onDispose(() => sub.cancel());
    try {
      return await repo.fetch();
    } catch (_) {
      return const AppSettings(languageCode: 'en_US');
    }
  }

  Future<void> setLanguage(String code) async {
    final repo = ref.read(settingsRepoProvider);
    await repo.update({'languageCode': code});
  }

  Future<void> setBool(String key, bool value) async {
    if (key == 'privateAccount') {
      await setPrivateAccount(value);
      return;
    }

    final repo = ref.read(settingsRepoProvider);
    await repo.update({key: value});
  }

  Future<void> setPrivateAccount(bool value) async {
    final currentSettings = state.asData?.value;
    if (currentSettings == null) return;
    if (_privacyUpdateInFlight) return;
    if (currentSettings.privateAccount == value) {
      ref.read(privacyUpdateStateProvider.notifier).state =
          const PrivacyUpdateState.idle();
      return;
    }

    final previousSettings = currentSettings;
    _privacyUpdateInFlight = true;
    _pendingPrivacyTarget = value;
    ref.read(privacyUpdateStateProvider.notifier).state = PrivacyUpdateState(
      status: PrivacyUpdateStatus.updating,
      targetValue: value,
    );

    // Optimistic update for immediate UI response.
    state = AsyncData(currentSettings.copyWith(privateAccount: value));

    final repo = ref.read(settingsRepoProvider);
    final uid = ref.read(currentUidProvider);

    try {
      await repo.updatePrivacy(isPrivate: value);
      if (uid != null) {
        // Keep dependent profile and visibility streams fresh.
        ref.invalidate(currentUserProfileProvider);
        ref.invalidate(userProfileByIdProvider(uid));
        ref.invalidate(followingIdsProvider);
        ref.invalidate(boomerangRepoProvider);
      }

      // Heavy sync is best-effort and must not block the toggle UX.
      if (uid != null) {
        unawaited(
          ref
              .read(boomerangRepoProvider)
              .syncOwnerPrivacy(uid: uid, isPrivate: value)
              .timeout(const Duration(seconds: 12))
              .catchError((_) {}),
        );
      }

      if (!value && uid != null) {
        unawaited(
          ref
              .read(followRepoProvider)
              .acceptAllPendingFor(uid)
              .timeout(const Duration(seconds: 8))
              .catchError((_) {}),
        );
      }

      ref.read(privacyUpdateStateProvider.notifier).state = PrivacyUpdateState(
        status: PrivacyUpdateStatus.success,
        targetValue: value,
      );
    } catch (e) {
      _pendingPrivacyTarget = null;
      state = AsyncData(previousSettings);
      ref.read(privacyUpdateStateProvider.notifier).state = PrivacyUpdateState(
        status: PrivacyUpdateStatus.failure,
        targetValue: previousSettings.privateAccount,
        message: _toUserMessage(e),
      );
    } finally {
      _privacyUpdateInFlight = false;
    }
  }

  String _toUserMessage(Object error) {
    if (error is SettingsRepoException) {
      return error.message;
    }
    if (error is TimeoutException) {
      return 'Network timeout while updating privacy. Please try again.';
    }
    return 'Could not update privacy right now. Please try again.';
  }

  void clearPrivacyUpdateState() {
    ref.read(privacyUpdateStateProvider.notifier).state =
        const PrivacyUpdateState.idle();
  }
}
