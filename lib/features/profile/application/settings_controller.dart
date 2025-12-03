import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/domain/app_settings.dart';
import 'package:boomerang/features/profile/infrastructure/settings_repo.dart';

final settingsRepoProvider = Provider<SettingsRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return SettingsRepo(fs, auth);
});

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepoProvider);
    // Keep state in sync with the Firestore stream
    final sub = repo.watch().listen((value) {
      state = AsyncData(value);
    });
    ref.onDispose(() => sub.cancel());
    return await repo.fetch();
  }

  Future<void> setLanguage(String code) async {
    final repo = ref.read(settingsRepoProvider);
    await repo.update({'languageCode': code});
  }

  Future<void> setBool(String key, bool value) async {
    final repo = ref.read(settingsRepoProvider);
    await repo.update({key: value});
  }
}
