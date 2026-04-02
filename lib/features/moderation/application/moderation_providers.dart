import 'package:boomerang/features/moderation/domain/moderation_repo.dart';
import 'package:boomerang/features/moderation/infrastructure/firestore_moderation_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final moderationRepoProvider = Provider<ModerationRepo>((ref) {
  final fs = ref.watch(firestoreProvider);
  return FirestoreModerationRepo(fs);
});

/// Live list of UIDs the current user has blocked.
final blockedUsersProvider = StreamProvider<List<String>>((ref) {
  final me = ref.watch(currentUserProfileProvider).value;
  if (me == null) return const Stream.empty();
  return ref.watch(moderationRepoProvider).watchBlockedUsers(me.uid);
});
