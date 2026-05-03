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
    String? videoFilter,
  }) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('poster', 'jpg');

    Future<bool> _tryPoster(String vf, {String seekTo = '0.1'}) async {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss', seekTo,
        '-i', inputPath,
        '-vf', vf,
        '-frames:v', '1',
        '-q:v', '2',
        outPath,
      ]);
      return ReturnCode.isSuccess(await session.getReturnCode()) &&
          File(outPath).existsSync() &&
          File(outPath).lengthSync() > 0;
    }

    final fullVf = [
      'scale=$targetWidth:-1',
      if (videoFilter != null && videoFilter.isNotEmpty) videoFilter,
    ].join(',');

    // Try seeking to 0.1 s first; fall back to frame 0 for very short videos.
    for (final seek in ['0.1', '0']) {
      if (await _tryPoster(fullVf, seekTo: seek)) return outPath;

      if (videoFilter != null && videoFilter.isNotEmpty) {
        if (await _tryPoster('scale=$targetWidth:-1', seekTo: seek)) {
          return outPath;
        }
      }
    }

    throw Exception('Poster generation failed');
  }

  // ---------------------------------------------------------------------------
  // Trim — hard-clips the input to [maxSeconds] so imported gallery videos
  // never exceed the boomerang segment budget (1.5 s → 3 s final loop).
  // Returns the original path unchanged when already short enough.
  // ---------------------------------------------------------------------------

  Future<String> trimToMaxDuration(
    String inputPath, {
    double maxSeconds = 1.5,
  }) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('trimmed', 'mp4');

    for (final enc in _encoderCandidates) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i', inputPath,
        '-t', maxSeconds.toStringAsFixed(2),
        '-an',
        ...enc,
        '-movflags', '+faststart',
        outPath,
      ]);
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await _hasVideoContent(outPath)) {
        return outPath;
      }
    }
    return inputPath;
  }

  // ---------------------------------------------------------------------------
  // Trim to a user-chosen window [startSeconds .. startSeconds + durationSeconds].
  // Used by the gallery trim screen so the user can pick which slice of a
  // longer video becomes the boomerang. Returns the original path if every
  // encoder candidate fails (caller is expected to handle that by treating
  // the returned path as the original, but FFmpeg succeeds in virtually
  // every real-world case).
  // ---------------------------------------------------------------------------

  Future<String> trimToWindow(
    String inputPath, {
    required double startSeconds,
    required double durationSeconds,
  }) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('trim_window', 'mp4');

    final start = startSeconds < 0 ? 0.0 : startSeconds;
    final duration = durationSeconds <= 0 ? 0.1 : durationSeconds;

    for (final enc in _encoderCandidates) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        // -ss before -i enables input-seek (fast, keyframe-accurate enough
        // for our short 0.3–1.5 s windows). -t caps the output duration.
        '-ss', start.toStringAsFixed(3),
        '-i', inputPath,
        '-t', duration.toStringAsFixed(3),
        '-an',
        ...enc,
        '-movflags', '+faststart',
        outPath,
      ]);
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await _hasVideoContent(outPath)) {
        return outPath;
      }
    }
    return inputPath;
  }

  // ---------------------------------------------------------------------------
  // Timeline thumbnails — extracts N evenly-spaced thumbnail JPEGs used by
  // the trim filmstrip. Single FFmpeg call via the fps filter so it stays
  // fast even on long source videos.
  // ---------------------------------------------------------------------------

  Future<List<String>> extractTimelineThumbnails(
    String inputPath, {
    required double durationSeconds,
    int count = 8,
    int heightPx = 80,
  }) async {
    _assertExists(inputPath);
    if (durationSeconds <= 0 || count <= 0) return const [];

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final prefix = 'ttb${ts}_';
    final pattern = '${tempDir.path}/$prefix' '%03d.jpg';

    // One frame every (duration / count) seconds → `count` frames total.
    final fps = count / durationSeconds;

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', inputPath,
      '-vf', 'fps=${fps.toStringAsFixed(4)},scale=-2:$heightPx',
      '-frames:v', '$count',
      '-q:v', '5',
      pattern,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      return const [];
    }

    final results = <String>[];
    for (int i = 1; i <= count; i++) {
      final path = '${tempDir.path}/$prefix${i.toString().padLeft(3, '0')}.jpg';
      if (File(path).existsSync()) results.add(path);
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Mirror — creates a horizontally flipped copy with all metadata resolved.
  // ---------------------------------------------------------------------------

  Future<String> mirrorInput(String inputPath) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('mirrored', 'mp4');

    // Try with -noautorotate first, then without, for each encoder
    for (final noAutoRotate in [true, false]) {
      for (final enc in _encoderCandidates) {
        final session = await FFmpegKit.executeWithArguments([
          '-y',
          if (noAutoRotate) '-noautorotate',
          '-i', inputPath,
          '-vf', 'hflip',
          if (noAutoRotate) ...['-metadata:s:v', 'rotate=0'],
          '-an',
          ...enc,
          '-movflags', '+faststart',
          outPath,
        ]);
        if (ReturnCode.isSuccess(await session.getReturnCode()) &&
            await _hasVideoContent(outPath)) {
          return outPath;
        }
      }
    }
    return inputPath;
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
    String? videoFilter,
  }) async {
    _assertExists(inputPath);

    final cyclePath = await _buildBoomerangViaFrames(
      inputPath,
      segmentSeconds: segmentSeconds,
      speed: speed,
      videoFilter: videoFilter,
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
    String? videoFilter,
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

      List<String> _buildExtractArgs(String? vf) => <String>[
        '-y',
        '-ss', '0',
        '-i', inputPath,
        '-frames:v', '$maxFrames',
        '-vsync', '0',
        if (vf != null && vf.isNotEmpty) ...['-vf', vf],
        '-q:v', '2',
        framePattern,
      ];

      final vfParts = <String>[
        if (scaleWidth != null) 'scale=$scaleWidth:-2',
        if (videoFilter != null && videoFilter.isNotEmpty) videoFilter,
      ];
      final fullVf = vfParts.isNotEmpty ? vfParts.join(',') : null;

      var extractSession = await FFmpegKit.executeWithArguments(
        _buildExtractArgs(fullVf),
      );
      var extractRc = await extractSession.getReturnCode();

      // If filter-based extraction fails, retry without color filter
      if (!ReturnCode.isSuccess(extractRc) && videoFilter != null && videoFilter.isNotEmpty) {
        _cleanupByPrefix(tempDir, framePrefix);
        final fallbackVf = scaleWidth != null ? 'scale=$scaleWidth:-2' : null;
        extractSession = await FFmpegKit.executeWithArguments(
          _buildExtractArgs(fallbackVf),
        );
        extractRc = await extractSession.getReturnCode();
      }

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
