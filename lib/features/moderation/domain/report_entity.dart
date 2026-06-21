enum ReportType { user, boomerang, comment }

enum ReportReason { spam, harassment, nudity, violence, hateSpeech, other }

enum ReportStatus { pending, reviewed, resolved, dismissed }

class ReportEntity {
  const ReportEntity({
    this.id,
    required this.reporterUid,
    required this.reportedUid,
    this.boomerangId,
    this.commentId,
    required this.type,
    required this.reason,
    this.details,
    this.status = ReportStatus.pending,
    required this.createdAt,
    this.reviewedAt,
    this.reviewerNotes,
  });

  final String? id;
  final String reporterUid;
  final String reportedUid;
  final String? boomerangId;
  final String? commentId;
  final ReportType type;
  final ReportReason reason;
  final String? details;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewerNotes;

  Map<String, dynamic> toMap() => {
        'reporterUid': reporterUid,
        'reportedUid': reportedUid,
        if (boomerangId != null) 'boomerangId': boomerangId,
        if (commentId != null) 'commentId': commentId,
        'type': type.name,
        'reason': reason.name,
        if (details != null && details!.isNotEmpty) 'details': details,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
      };

  static ReportReason reasonFromString(String value) {
    return ReportReason.values.firstWhere(
      (r) => r.name == value,
      orElse: () => ReportReason.other,
    );
  }

  static String reasonLabel(ReportReason reason) {
    switch (reason) {
      case ReportReason.spam:
        return 'Spam';
      case ReportReason.harassment:
        return 'Harassment';
      case ReportReason.nudity:
        return 'Nudity';
      case ReportReason.violence:
        return 'Violence';
      case ReportReason.hateSpeech:
        return 'Hate speech';
      case ReportReason.other:
        return 'Other';
    }
  }
}
