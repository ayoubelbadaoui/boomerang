// ignore_for_file: unnecessary_brace_in_string_interps

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

  /// Extract a lightweight poster image from the input video for use as a preview.
  ///
  /// - Uses FFmpeg 'thumbnail' filter to pick a representative frame
  /// - Scales down to [targetWidth] while preserving aspect ratio
  /// - Outputs a small JPEG to a temporary file and returns its path
  Future<String> generatePoster(
    String inputPath, {
    int targetWidth = 360,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw Exception('Input file does not exist: $inputPath');
    }
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/poster_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Pick a thumbnail frame and scale down to reduce bytes. Use mjpeg encoder for speed.
    final cmd = [
      '-y',
      '-i',
      '"$inputPath"',
      '-vf',
      '"thumbnail,scale=${targetWidth}:-1"',
      '-frames:v',
      '1',
      '-q:v',
      '6',
      '"$outPath"',
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception(
        'FFmpeg poster gen failed (code: ${rc?.getValue()})\n$logs',
      );
    }
    return outPath;
  }

  /// Build a real "boomerang" clip by concatenating a forward segment with its reversed copy.
  ///
  /// - Trims to the first [segmentSeconds] seconds to keep the loop snappy
  /// - Removes audio for consistency across concat and playback
  /// - Re-encodes to yuv420p H.264 with faststart for mobile compatibility
  Future<String> makeBoomerang(
    String inputPath, {
    double segmentSeconds = 1.6,
    int fps = 30,
    double totalDurationSeconds = 6.0,
    double speed = 1.0,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw Exception('Input file does not exist: $inputPath');
    }

    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/boomerang_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final singleCyclePath =
        '${tempDir.path}/boomerang_cycle_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Use a single-pass filter_complex to create forward + reverse and concat
    // Notes:
    //  - format=yuv420p improves compatibility with iOS/Android decoders
    //  - -an strips audio to avoid A/V concat issues and boomerang audio oddities
    final speedStr = speed.toStringAsFixed(3);
    final filterBase =
        "[0:v]trim=start=0:end=${segmentSeconds.toStringAsFixed(2)},setpts=PTS-STARTPTS,split=2[fwd][tmp];[tmp]reverse[rev];[fwd][rev]concat=n=2:v=1:a=0,format=yuv420p";
    final filter =
        speed == 1.0 ? "$filterBase[v]" : "$filterBase,setpts=PTS/$speedStr[v]";

    // Quote paths to handle spaces
    final cmd = [
      '-y',
      '-i',
      '"$inputPath"',
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
      '"$singleCyclePath"',
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg failed (code: ${rc?.getValue()})\n$logs');
    }

    // If the user wants a longer clip, repeat the single boomerang cycle
    final cycleDuration =
        (2 * segmentSeconds) /
        (speed <= 0 ? 1.0 : speed); // forward + reverse adjusted by speed
    final cyclesNeeded = (totalDurationSeconds / cycleDuration).ceil().clamp(
      1,
      12,
    );
    if (cyclesNeeded <= 1) {
      // Move singleCycle to final outPath
      await File(singleCyclePath).copy(outPath);
      return outPath;
    }

    // Prepare concat list file
    final listFile = File(
      '${tempDir.path}/boomerang_list_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    final buffer = StringBuffer();
    for (int i = 0; i < cyclesNeeded; i++) {
      buffer.writeln("file '$singleCyclePath'");
    }
    await listFile.writeAsString(buffer.toString());

    final concatCmd = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      '"${listFile.path}"',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '"$outPath"',
    ].join(' ');

    final concatSession = await FFmpegKit.execute(concatCmd);
    final concatRc = await concatSession.getReturnCode();
    if (!ReturnCode.isSuccess(concatRc)) {
      final logs = await concatSession.getAllLogsAsString();
      throw Exception(
        'FFmpeg concat failed (code: ${concatRc?.getValue()})\n$logs',
      );
    }

    // Cleanup
    try {
      await listFile.delete();
      await File(singleCyclePath).delete();
    } catch (_) {}

    return outPath;
  }
}
