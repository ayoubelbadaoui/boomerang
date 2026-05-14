import 'dart:math' as math;

/// Generates the per-session, per-surface seed used to make the
/// exploration jitter deterministic across a single user session.
///
/// Same seed throughout a session ⇒ page-2 doesn't reshuffle page-1.
/// New seed on pull-to-refresh ⇒ top items can re-arrange.
class SessionSeed {
  SessionSeed._(this.value);

  final int value;

  factory SessionSeed.bootstrap({
    required String uid,
    required String surface,
    DateTime? now,
  }) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    // Keep the seed bounded so it fits in any int representation we
    // multiply with hashCodes later.
    final raw = uid.hashCode ^ surface.hashCode ^ t;
    return SessionSeed._(raw & 0x7fffffff);
  }

  SessionSeed rotated() {
    final next = (math.Random(value).nextInt(0x7fffffff)) ^ value;
    return SessionSeed._(next & 0x7fffffff);
  }

  @override
  String toString() => 'SessionSeed($value)';
}
