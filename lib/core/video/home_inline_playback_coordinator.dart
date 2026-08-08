import 'package:flutter/foundation.dart';

/// Limits concurrent muted Home-feed loops so Android MediaCodec stays stable
/// while neighbors stay warm for consistent swipe-in playback.
///
/// Ranking: lower [centerDistance] wins among on-screen candidates. The active
/// set is a hard top-[maxActive] — media widgets own pause/dispose hysteresis.
class HomeInlinePlaybackCoordinator {
  HomeInlinePlaybackCoordinator._();
  static final HomeInlinePlaybackCoordinator instance =
      HomeInlinePlaybackCoordinator._();

  static const int maxActive = 3;

  final Map<String, _HomePlaybackCandidate> _candidates = {};
  final Set<String> _active = <String>{};

  /// Whether [id] currently holds a play slot.
  bool isActive(String id) => _active.contains(id);

  /// Report visibility for a Home card. [onChanged] is invoked when that
  /// card's active-slot status flips (gained or lost).
  void update({
    required String id,
    required double visibleFraction,
    required double centerDistance,
    required VoidCallback onChanged,
  }) {
    final existing = _candidates[id];
    _candidates[id] = _HomePlaybackCandidate(
      id: id,
      visibleFraction: visibleFraction,
      centerDistance: centerDistance,
      onChanged: onChanged,
    );

    if (existing == null ||
        (existing.visibleFraction - visibleFraction).abs() > 0.01 ||
        (existing.centerDistance - centerDistance).abs() > 8) {
      _recompute();
    }
  }

  void unregister(String id) {
    final had = _candidates.remove(id) != null;
    final wasActive = _active.remove(id);
    if (had || wasActive) _recompute();
  }

  void _recompute() {
    final ranked =
        _candidates.values
            .where((c) => c.visibleFraction > 0)
            .toList(growable: false)
          ..sort((a, b) {
            final byDist = a.centerDistance.compareTo(b.centerDistance);
            if (byDist != 0) return byDist;
            return b.visibleFraction.compareTo(a.visibleFraction);
          });

    final desired = <String>{
      for (final c in ranked.take(maxActive)) c.id,
    };

    final gained = desired.difference(_active);
    final lost = _active.difference(desired);
    if (gained.isEmpty && lost.isEmpty) return;

    _active
      ..clear()
      ..addAll(desired);

    for (final id in [...gained, ...lost]) {
      _candidates[id]?.onChanged();
    }
  }
}

class _HomePlaybackCandidate {
  const _HomePlaybackCandidate({
    required this.id,
    required this.visibleFraction,
    required this.centerDistance,
    required this.onChanged,
  });

  final String id;
  final double visibleFraction;
  final double centerDistance;
  final VoidCallback onChanged;
}
