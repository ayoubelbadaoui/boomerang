import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Simple placeholder processor that simulates a boomerang effect by
/// duplicating the input video into a new temporary file path.
///
/// Replace the implementation with real processing (e.g., ffmpeg) later.
class BoomerangProcessor {
  const BoomerangProcessor();

  /// Build a real "boomerang" clip by concatenating a forward segment with its reversed copy.
  ///
  /// - Trims to the first [segmentSeconds] seconds to keep the loop snappy
  /// - Removes audio for consistency across concat and playback
  /// - Re-encodes to yuv420p H.264 with faststart for mobile compatibility
  Future<String> makeBoomerang(
    String inputPath, {
    double segmentSeconds = 1.6,
    int fps = 30,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw Exception('Input file does not exist: $inputPath');
    }

    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/boomerang_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Use a single-pass filter_complex to create forward + reverse and concat
    // Notes:
    //  - format=yuv420p improves compatibility with iOS/Android decoders
    //  - -an strips audio to avoid A/V concat issues and boomerang audio oddities
    final filter =
        "[0:v]trim=start=0:end=${segmentSeconds.toStringAsFixed(2)},setpts=PTS-STARTPTS,split=2[fwd][tmp];[tmp]reverse[rev];[fwd][rev]concat=n=2:v=1:a=0,format=yuv420p[v]";

    // Quote paths to handle spaces
    final cmd = [
      '-y',
      '-i',
      '$inputPath',
      '-filter_complex',
      '"$filter"',
      '-map',
      '"[v]"',
      '-r',
      '$fps',
      '-an',
      '-c:v',
      'libx264',
      '-preset',
      'faster',
      '-movflags',
      '+faststart',
      '$outPath',
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg failed (code: ${rc?.getValue()})\n$logs');
    }

    return outPath;
  }
}
