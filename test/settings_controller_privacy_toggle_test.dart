import 'dart:async';

import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:boomerang/features/profile/domain/app_settings.dart';
import 'package:boomerang/features/profile/infrastructure/settings_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSettingsRepo implements SettingsRepo {
  FakeSettingsRepo({AppSettings? initial})
      : _current = initial ?? const AppSettings(languageCode: 'en_US');

  final StreamController<AppSettings> _streamController =
      StreamController<AppSettings>.broadcast();
  AppSettings _current;
  int updatePrivacyCallCount = 0;
  Completer<void>? nextUpdatePrivacyCompleter;
  Object? nextUpdatePrivacyError;

  @override
  Future<AppSettings> fetch() async => _current;

  @override
  Stream<AppSettings> watch() => _streamController.stream;

  @override
  Future<void> update(Map<String, dynamic> data) async {
    if (data.containsKey('privateAccount')) {
      _current = _current.copyWith(privateAccount: data['privateAccount'] == true);
      _streamController.add(_current);
    }
  }

  @override
  Future<void> updatePrivacy({required bool isPrivate}) async {
    updatePrivacyCallCount++;
    final error = nextUpdatePrivacyError;
    if (error != null) {
      nextUpdatePrivacyError = null;
      throw error;
    }

    final completer = nextUpdatePrivacyCompleter;
    if (completer != null) {
      await completer.future;
      nextUpdatePrivacyCompleter = null;
    }

    _current = _current.copyWith(privateAccount: isPrivate);
    _streamController.add(_current);
  }

  Future<void> dispose() async {
    await _streamController.close();
  }
}

void main() {
  group('SettingsController privacy toggle', () {
    late FakeSettingsRepo fakeRepo;
    late ProviderContainer container;

    setUp(() async {
      fakeRepo = FakeSettingsRepo();
      container = ProviderContainer(
        overrides: [
          settingsRepoProvider.overrideWithValue(fakeRepo),
          currentUidProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeRepo.dispose);
      await container.read(settingsControllerProvider.future);
    });

    test('optimistic update is immediate and converges on success', () async {
      final notifier = container.read(settingsControllerProvider.notifier);
      final gate = Completer<void>();
      fakeRepo.nextUpdatePrivacyCompleter = gate;

      final pending = notifier.setPrivateAccount(true);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(settingsControllerProvider).requireValue.privateAccount,
        isTrue,
      );
      expect(
        container.read(privacyUpdateStateProvider).status,
        PrivacyUpdateStatus.updating,
      );

      gate.complete();
      await pending;

      expect(
        container.read(settingsControllerProvider).requireValue.privateAccount,
        isTrue,
      );
      expect(
        container.read(privacyUpdateStateProvider).status,
        PrivacyUpdateStatus.success,
      );
    });

    test('failure rolls back optimistic value and sets error state', () async {
      final notifier = container.read(settingsControllerProvider.notifier);
      fakeRepo.nextUpdatePrivacyError =
          const SettingsRepoException('Network timeout while updating privacy. Please try again.');

      await notifier.setPrivateAccount(true);

      expect(
        container.read(settingsControllerProvider).requireValue.privateAccount,
        isFalse,
      );
      final state = container.read(privacyUpdateStateProvider);
      expect(state.status, PrivacyUpdateStatus.failure);
      expect(state.message, 'Network timeout while updating privacy. Please try again.');
    });

    test('ignores concurrent toggle while update is in flight', () async {
      final notifier = container.read(settingsControllerProvider.notifier);
      final gate = Completer<void>();
      fakeRepo.nextUpdatePrivacyCompleter = gate;

      final first = notifier.setPrivateAccount(true);
      await Future<void>.delayed(Duration.zero);
      await notifier.setPrivateAccount(false);

      expect(fakeRepo.updatePrivacyCallCount, 1);

      gate.complete();
      await first;

      expect(
        container.read(settingsControllerProvider).requireValue.privateAccount,
        isTrue,
      );
    });
  });
}
