import 'dart:async';

import 'package:boomerang/features/profile/application/profile_refresh_controller.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileRefreshController', () {
    ProviderContainer containerFor({
      required ProfileRefreshFetcher fetcher,
      UserProfile? currentUser,
    }) {
      return ProviderContainer(
        overrides: [
          profileRefreshFetcherProvider.overrideWithValue(fetcher),
          profileRefreshInvalidatorProvider.overrideWithValue(
            (ref, userId, me) {},
          ),
          currentUserProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(currentUser),
          ),
        ],
      );
    }

    test('dedupes concurrent refresh calls per user', () async {
      final completer = Completer<ProfileRefreshFetchResult>();
      var fetchCalls = 0;
      final container = containerFor(
        fetcher: (userId, {required forceRefresh}) async {
          fetchCalls++;
          return completer.future;
        },
      );
      addTearDown(container.dispose);
      await container.read(currentUserProfileProvider.future);

      final controller = container.read(
        profileRefreshControllerProvider.notifier,
      );
      final first = controller.refreshProfile(
        'target_user',
        forceRefresh: true,
      );
      final second = controller.refreshProfile(
        'target_user',
        forceRefresh: true,
      );

      expect(fetchCalls, 1);
      completer.complete(
        const ProfileRefreshFetchResult(
          status: ProfileRefreshStatus.refreshedFromServer,
        ),
      );
      await Future.wait([first, second]);
      expect(fetchCalls, 1);
    });

    test('self open refreshes only after social mutation mark', () async {
      var fetchCalls = 0;
      final me = UserProfile(uid: 'me_uid', fullName: 'Me', nickname: 'me');
      final container = containerFor(
        currentUser: me,
        fetcher: (userId, {required forceRefresh}) async {
          fetchCalls++;
          return const ProfileRefreshFetchResult(
            status: ProfileRefreshStatus.refreshedFromServer,
          );
        },
      );
      addTearDown(container.dispose);
      await container.read(currentUserProfileProvider.future);

      final controller = container.read(
        profileRefreshControllerProvider.notifier,
      );

      await controller.onProfileOpened('me_uid');
      expect(fetchCalls, 0);

      controller.markSocialMutation('me_uid');
      await controller.onProfileOpened('me_uid');
      expect(fetchCalls, 1);
    });

    test(
      'failed refresh keeps social mutation pending and records error',
      () async {
        final container = containerFor(
          fetcher: (userId, {required forceRefresh}) async {
            return const ProfileRefreshFetchResult(
              status: ProfileRefreshStatus.failed,
              errorMessage: 'network down',
            );
          },
        );
        addTearDown(container.dispose);
        await container.read(currentUserProfileProvider.future);

        final controller = container.read(
          profileRefreshControllerProvider.notifier,
        );
        controller.markSocialMutation('target_user');
        await controller.refreshProfile('target_user', forceRefresh: true);

        final state = container.read(profileRefreshControllerProvider);
        expect(state.pendingSocialMutation.contains('target_user'), true);
        expect(
          state.lastRefreshStatus['target_user'],
          ProfileRefreshStatus.failed,
        );
        expect(state.lastRefreshError['target_user'], 'network down');
        expect(
          container.read(profileRefreshStatusProvider('target_user')),
          ProfileRefreshStatus.failed,
        );
        expect(
          container.read(profileRefreshErrorProvider('target_user')),
          'network down',
        );
      },
    );
  });
}
