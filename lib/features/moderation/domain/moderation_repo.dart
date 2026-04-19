import 'package:boomerang/features/moderation/domain/report_entity.dart';

abstract class ModerationRepo {
  Future<void> submitReport(ReportEntity report);

  Future<void> blockUser({
    required String blockerUid,
    required String blockedUid,
    String? blockedName,
    String? blockedAvatar,
  });

  Future<void> unblockUser({
    required String blockerUid,
    required String blockedUid,
  });

  Stream<List<String>> watchBlockedUsers(String uid);

  Future<bool> isBlocked({
    required String checkerUid,
    required String targetUid,
  });
}
