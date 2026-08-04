import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoomerangProcessor tuning', () {
    test('encoder candidates prefer x264 quality path first', () {
      final candidates = BoomerangProcessor.debugEncoderArgsFor(
        width: 1920,
        height: 1080,
        fps: 30,
        favorQuality: true,
      );
      expect(candidates, isNotEmpty);
      expect(candidates.first, containsAllInOrder(['-c:v', 'libx264']));
      expect(candidates.first, containsAllInOrder(['-crf', '18']));
      expect(candidates.first, containsAllInOrder(['-pix_fmt', 'yuv420p']));
      expect(candidates.first, containsAllInOrder(['-g', '60']));
    });

    test('quality tuning uses softer caps than preview mode', () {
      final quality = BoomerangProcessor.debugTuning(
        width: 1920,
        height: 1080,
        fps: 30,
        favorQuality: true,
      );
      final preview = BoomerangProcessor.debugTuning(
        width: 1920,
        height: 1080,
        fps: 30,
        favorQuality: false,
      );

      expect((quality['crf'] as int), lessThan(preview['crf'] as int));
      final qualityEnc = BoomerangProcessor.debugEncoderArgsFor(
        width: 1920,
        height: 1080,
        fps: 30,
        favorQuality: true,
      );
      final previewEnc = BoomerangProcessor.debugEncoderArgsFor(
        width: 1920,
        height: 1080,
        fps: 30,
        favorQuality: false,
      );
      expect(qualityEnc.first, containsAllInOrder(['-preset', 'slow']));
      expect(previewEnc.first, containsAllInOrder(['-preset', 'medium']));
    });

    test('poster width adapts above old 720 hard cap', () {
      final width = BoomerangProcessor.debugPosterTargetWidth(
        sourceWidth: 1920,
      );
      expect(width, greaterThan(720));
      expect(width, lessThanOrEqualTo(1600));
    });
  });
}
