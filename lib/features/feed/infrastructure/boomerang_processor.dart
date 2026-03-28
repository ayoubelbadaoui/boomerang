import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class BoomerangProcessor {
  const BoomerangProcessor();

  static List<List<String>> get _encoderCandidates {
    if (Platform.isIOS || Platform.isMacOS) {
      return [
        ['-c:v', 'h264_videotoolbox', '-b:v', '6M'],
        ['-c:v', 'mpeg4', '-q:v', '2'],
      ];
    }
    return [
      ['-c:v', 'libx264', '-preset', 'fast', '-crf', '18'],
      ['-c:v', 'mpeg4', '-q:v', '2'],
    ];
  }

  // ---------------------------------------------------------------------------
  // Poster — seek to 0.1s and grab 1 frame (no thumbnail filter — it drops
  // frames on Android VFR videos just like the fps filter did).
  // ---------------------------------------------------------------------------

  Future<String> generatePoster(
    String inputPath, {
    int targetWidth = 720,
  }) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('poster', 'jpg');

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', '0.1',
      '-i', inputPath,
      '-vf', 'scale=$targetWidth:-1',
      '-frames:v', '1',
      '-q:v', '2',
      outPath,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !File(outPath).existsSync()) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Poster failed\n$logs');
    }
    return outPath;
  }

  // ---------------------------------------------------------------------------
  // Preview (single cycle, low-res, for editor looping)
  // ---------------------------------------------------------------------------

  Future<String> makePreview(
    String inputPath, {
    double segmentSeconds = 1.6,
    double speed = 1.0,
    int previewWidth = 480,
  }) async {
    _assertExists(inputPath);
    return _buildBoomerangViaFrames(
      inputPath,
      segmentSeconds: segmentSeconds,
      speed: speed,
      scaleWidth: previewWidth,
    );
  }

  // ---------------------------------------------------------------------------
  // Final boomerang (full-res, looped to target duration)
  // ---------------------------------------------------------------------------

  Future<String> makeBoomerang(
    String inputPath, {
    double segmentSeconds = 1.6,
    int fps = 30,
    double totalDurationSeconds = 6.0,
    double speed = 1.0,
  }) async {
    _assertExists(inputPath);

    final cyclePath = await _buildBoomerangViaFrames(
      inputPath,
      segmentSeconds: segmentSeconds,
      speed: speed,
    );

    final cycleDuration = (2 * segmentSeconds) / (speed <= 0 ? 1.0 : speed);
    final cycles = (totalDurationSeconds / cycleDuration).ceil().clamp(1, 12);
    if (cycles <= 1) return cyclePath;

    final outPath = await _tmpPath('boomerang', 'mp4');
    final loopSession = await FFmpegKit.executeWithArguments([
      '-y',
      '-stream_loop', '${cycles - 1}',
      '-i', cyclePath,
      '-c', 'copy',
      '-fflags', '+genpts',
      '-movflags', '+faststart',
      outPath,
    ]);
    if (!ReturnCode.isSuccess(await loopSession.getReturnCode())) {
      return cyclePath;
    }
    try { await File(cyclePath).delete(); } catch (_) {}
    return outPath;
  }

  // ---------------------------------------------------------------------------
  // Core: frame-extraction approach.
  //
  //  1. Extract raw frames as JPEGs (no fps filter — Android VFR breaks it)
  //  2. Build boomerang sequence in Dart (forward + reverse file copies)
  //  3. Encode image sequence to video
  // ---------------------------------------------------------------------------

  Future<String> _buildBoomerangViaFrames(
    String inputPath, {
    required double segmentSeconds,
    required double speed,
    int? scaleWidth,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final framePrefix = 'bfr${ts}_';
    final seqPrefix = 'bsq${ts}_';

    try {
      // Step 1: extract raw frames. -ss 0 before -i resets the timestamp origin
      // (needed for Android VFR cameras with wall-clock DTS). -vsync 0 prevents
      // frame dropping. -frames:v limits by count instead of duration (which
      // fails with VFR timestamps).
      final maxFrames = (segmentSeconds * 60).ceil();
      final framePattern = '${tempDir.path}/$framePrefix%05d.jpg';
      final extractArgs = <String>[
        '-y',
        '-ss', '0',
        '-i', inputPath,
        '-frames:v', '$maxFrames',
        '-vsync', '0',
        if (scaleWidth != null) ...['-vf', 'scale=$scaleWidth:-2'],
        '-q:v', '2',
        framePattern,
      ];

      final extractSession =
          await FFmpegKit.executeWithArguments(extractArgs);
      final extractRc = await extractSession.getReturnCode();
      if (!ReturnCode.isSuccess(extractRc)) {
        final logs = await extractSession.getAllLogsAsString();
        throw Exception('Frame extraction failed (${extractRc?.getValue()})\n$logs');
      }

      // Collect extracted frames.
      final frames = tempDir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.path.split('/').last;
            return name.startsWith(framePrefix) && name.endsWith('.jpg');
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (frames.isEmpty) {
        final logs = await extractSession.getAllLogsAsString() ?? '';
        throw Exception(
          'Frame extraction produced 0 files.\n'
          'rc: ${extractRc?.getValue()}, pattern: $framePattern\n'
          '${logs.length > 500 ? logs.substring(logs.length - 500) : logs}',
        );
      }

      // Step 2: build forward + reverse sequence.
      int seqIndex = 1;
      String seqName(int i) =>
          '$seqPrefix${i.toString().padLeft(5, '0')}.jpg';

      for (final f in frames) {
        await f.copy('${tempDir.path}/${seqName(seqIndex++)}');
      }
      for (int i = frames.length - 2; i >= 0; i--) {
        await frames[i].copy('${tempDir.path}/${seqName(seqIndex++)}');
      }

      // Step 3: encode image sequence → video.
      final outPath = await _tmpPath('cycle', 'mp4');
      final nativeFps = frames.length / segmentSeconds;
      final effectiveFps = (speed == 1.0 ? nativeFps : nativeFps * speed)
          .clamp(10.0, 120.0);
      final fpsStr = effectiveFps.toStringAsFixed(2);
      final seqPattern = '${tempDir.path}/$seqPrefix%05d.jpg';

      String? lastLogs;
      for (final enc in _encoderCandidates) {
        final encSession = await FFmpegKit.executeWithArguments([
          '-y',
          '-framerate', fpsStr,
          '-i', seqPattern,
          '-pix_fmt', 'yuv420p',
          '-r', fpsStr,
          '-an',
          ...enc,
          '-movflags', '+faststart',
          outPath,
        ]);
        if (ReturnCode.isSuccess(await encSession.getReturnCode()) &&
            await _hasVideoContent(outPath)) {
          return outPath;
        }
        lastLogs = await encSession.getAllLogsAsString();
      }

      throw Exception('Image sequence encoding failed.\n$lastLogs');
    } finally {
      _cleanupByPrefix(tempDir, framePrefix);
      _cleanupByPrefix(tempDir, seqPrefix);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static void _assertExists(String path) {
    if (!File(path).existsSync()) {
      throw Exception('Input file does not exist: $path');
    }
  }

  static Future<String> _tmpPath(String label, String ext) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/${label}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  static Future<bool> _hasVideoContent(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    return (await file.length()) > 10240;
  }

  static void _cleanupByPrefix(Directory dir, String prefix) {
    try {
      for (final f in dir.listSync()) {
        if (f is File && f.path.split('/').last.startsWith(prefix)) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }
}
