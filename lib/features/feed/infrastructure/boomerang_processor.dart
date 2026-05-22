import 'dart:io';
import 'dart:developer' show log;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class BoomerangProcessor {
  const BoomerangProcessor();
  static const _logName = 'BoomerangProcessor';

  static List<List<String>> _encoderCandidates({
    required _EncodeTuning tuning,
    required bool favorQuality,
  }) {
    final common = <String>[
      '-pix_fmt',
      'yuv420p',
      '-r',
      tuning.fpsString,
      '-g',
      '${tuning.gop}',
      '-keyint_min',
      '${tuning.minKeyint}',
      '-sc_threshold',
      '0',
    ];

    final x264Path = <String>[
      '-c:v',
      'libx264',
      '-preset',
      favorQuality ? 'slow' : 'medium',
      '-crf',
      '${tuning.crf}',
      '-maxrate',
      tuning.maxBitrate,
      '-bufsize',
      tuning.bufferSize,
      '-profile:v',
      'high',
      ...common,
    ];

    if (Platform.isIOS || Platform.isMacOS) {
      return [
        x264Path,
        [
          '-c:v',
          'h264_videotoolbox',
          '-profile:v',
          'high',
          '-b:v',
          tuning.targetBitrate,
          '-maxrate',
          tuning.maxBitrate,
          '-bufsize',
          tuning.bufferSize,
          ...common,
        ],
        ['-c:v', 'mpeg4', '-q:v', favorQuality ? '2' : '3', ...common],
      ];
    }
    return [
      x264Path,
      ['-c:v', 'mpeg4', '-q:v', favorQuality ? '2' : '3', ...common],
    ];
  }

  static int debugPosterTargetWidth({
    required int sourceWidth,
    int maxWidth = 1600,
  }) => _adaptivePosterWidth(sourceWidth, maxWidth: maxWidth);

  static List<List<String>> debugEncoderArgsFor({
    required int width,
    required int height,
    required double fps,
    required bool favorQuality,
  }) {
    final tuning = _tuningFor(
      width: width,
      height: height,
      fps: fps,
      favorQuality: favorQuality,
    );
    return _encoderCandidates(tuning: tuning, favorQuality: favorQuality);
  }

  static Map<String, Object> debugTuning({
    required int width,
    required int height,
    required double fps,
    required bool favorQuality,
  }) {
    final tuning = _tuningFor(
      width: width,
      height: height,
      fps: fps,
      favorQuality: favorQuality,
    );
    return <String, Object>{
      'targetBitrate': tuning.targetBitrate,
      'maxBitrate': tuning.maxBitrate,
      'bufferSize': tuning.bufferSize,
      'crf': tuning.crf,
      'gop': tuning.gop,
      'minKeyint': tuning.minKeyint,
      'fps': tuning.fps,
    };
  }

  // ---------------------------------------------------------------------------
  // Poster — seek to 0.1s and grab 1 frame (no thumbnail filter — it drops
  // frames on Android VFR videos just like the fps filter did).
  // ---------------------------------------------------------------------------

  Future<String> generatePoster(
    String inputPath, {
    int? targetWidth,
    int maxWidth = 1600,
    int jpegQuality = 2,
    String? videoFilter,
  }) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('poster', 'jpg');
    final sourceStats = await _probeVideoStats(inputPath);
    final resolvedTargetWidth =
        targetWidth ??
        _adaptivePosterWidth(sourceStats.width, maxWidth: maxWidth);
    final scaleFilter = 'scale=$resolvedTargetWidth:-2:flags=lanczos';

    Future<bool> tryPoster(String vf, {String seekTo = '0.1'}) async {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss',
        seekTo,
        '-i',
        inputPath,
        '-vf',
        vf,
        '-frames:v',
        '1',
        '-q:v',
        '$jpegQuality',
        outPath,
      ]);
      return ReturnCode.isSuccess(await session.getReturnCode()) &&
          File(outPath).existsSync() &&
          File(outPath).lengthSync() > 0;
    }

    final fullVf = [
      scaleFilter,
      if (videoFilter != null && videoFilter.isNotEmpty) videoFilter,
    ].join(',');

    // Try seeking to 0.1 s first; fall back to frame 0 for very short videos.
    for (final seek in ['0.1', '0']) {
      if (await tryPoster(fullVf, seekTo: seek)) {
        await _logOutputStats(label: 'poster', path: outPath);
        return outPath;
      }

      if (videoFilter != null && videoFilter.isNotEmpty) {
        if (await tryPoster(scaleFilter, seekTo: seek)) {
          await _logOutputStats(label: 'poster', path: outPath);
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

    // Fast path: for t=0 trims this avoids a quality-loss re-encode.
    final copySession = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      inputPath,
      '-t',
      maxSeconds.toStringAsFixed(2),
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      outPath,
    ]);
    if (ReturnCode.isSuccess(await copySession.getReturnCode()) &&
        await _hasVideoContent(outPath)) {
      return outPath;
    }

    final sourceStats = await _probeVideoStats(inputPath);
    final tuning = _tuningFor(
      width: sourceStats.width,
      height: sourceStats.height,
      fps: sourceStats.fps,
      favorQuality: true,
    );
    for (final enc in _encoderCandidates(tuning: tuning, favorQuality: true)) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-t',
        maxSeconds.toStringAsFixed(2),
        '-an',
        ...enc,
        '-movflags',
        '+faststart',
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
  // Normalize source media into an app-safe MP4 (H.264 + AAC).
  // Used for gallery/shared videos so downstream trim/processing receives a
  // stable local file regardless of source URI/container/codec.
  // ---------------------------------------------------------------------------

  Future<String> transcodeToSafeMp4(String inputPath) async {
    _assertExists(inputPath);
    final outPath = await _tmpPath('normalized', 'mp4');
    final sourceStats = await _probeVideoStats(inputPath);
    final tuning = _tuningFor(
      width: sourceStats.width,
      height: sourceStats.height,
      fps: sourceStats.fps,
      favorQuality: true,
    );

    String? lastLogs;
    for (final enc in _encoderCandidates(tuning: tuning, favorQuality: true)) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        ...enc,
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-ac',
        '2',
        '-ar',
        '44100',
        '-movflags',
        '+faststart',
        outPath,
      ]);
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await _hasVideoContent(outPath)) {
        return outPath;
      }
      lastLogs = await session.getAllLogsAsString();
    }

    throw Exception('Safe transcode failed.\n$lastLogs');
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
    final sourceStats = await _probeVideoStats(inputPath);
    final tuning = _tuningFor(
      width: sourceStats.width,
      height: sourceStats.height,
      fps: sourceStats.fps,
      favorQuality: true,
    );

    for (final enc in _encoderCandidates(tuning: tuning, favorQuality: true)) {
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
    final pattern =
        '${tempDir.path}/$prefix'
        '%03d.jpg';

    // One frame every (duration / count) seconds → `count` frames total.
    final fps = count / durationSeconds;

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      inputPath,
      '-vf',
      'fps=${fps.toStringAsFixed(4)},scale=-2:$heightPx',
      '-frames:v',
      '$count',
      '-q:v',
      '5',
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
    final sourceStats = await _probeVideoStats(inputPath);
    final tuning = _tuningFor(
      width: sourceStats.width,
      height: sourceStats.height,
      fps: sourceStats.fps,
      favorQuality: true,
    );

    // Try with -noautorotate first, then without, for each encoder
    for (final noAutoRotate in [true, false]) {
      for (final enc in _encoderCandidates(
        tuning: tuning,
        favorQuality: true,
      )) {
        final session = await FFmpegKit.executeWithArguments([
          '-y',
          if (noAutoRotate) '-noautorotate',
          '-i',
          inputPath,
          '-vf',
          'hflip',
          if (noAutoRotate) ...['-metadata:s:v', 'rotate=0'],
          '-an',
          ...enc,
          '-movflags',
          '+faststart',
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
      targetFps: 24,
      favorQuality: false,
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
      targetFps: fps,
      favorQuality: true,
    );

    final estimatedCycleDuration =
        (2 * segmentSeconds) / (speed <= 0 ? 1.0 : speed);
    final probedCycleDuration = await _probeDurationSeconds(cyclePath);
    final cycleDuration =
        (probedCycleDuration != null && probedCycleDuration > 0.02)
            ? probedCycleDuration
            : estimatedCycleDuration;
    final cycles = (totalDurationSeconds / cycleDuration).ceil().clamp(1, 120);
    if (cycles <= 1) {
      await _logOutputStats(label: 'boomerang', path: cyclePath);
      return cyclePath;
    }

    final outPath = await _tmpPath('boomerang', 'mp4');
    final loopSession = await FFmpegKit.executeWithArguments([
      '-y',
      '-stream_loop',
      '${cycles - 1}',
      '-i',
      cyclePath,
      '-c',
      'copy',
      '-fflags',
      '+genpts',
      '-movflags',
      '+faststart',
      outPath,
    ]);
    if (!ReturnCode.isSuccess(await loopSession.getReturnCode())) {
      return cyclePath;
    }
    await _logOutputStats(label: 'boomerang', path: outPath);
    try {
      await File(cyclePath).delete();
    } catch (_) {}
    return outPath;
  }

  // ---------------------------------------------------------------------------
  // Core: frame-extraction approach.
  //
  //  1. Extract raw frames as PNGs (no fps filter — Android VFR breaks it)
  //  2. Build boomerang sequence in Dart (forward + reverse file copies)
  //  3. Encode image sequence to video
  // ---------------------------------------------------------------------------

  Future<String> _buildBoomerangViaFrames(
    String inputPath, {
    required double segmentSeconds,
    required double speed,
    int? scaleWidth,
    String? videoFilter,
    required int targetFps,
    required bool favorQuality,
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
      final cappedFps = targetFps.clamp(12, 60);
      final maxFrames = (segmentSeconds * cappedFps).ceil().clamp(12, 180);
      final framePattern = '${tempDir.path}/$framePrefix%05d.png';

      List<String> buildExtractArgs(String? vf) => <String>[
        '-y',
        '-ss',
        '0',
        '-i',
        inputPath,
        '-frames:v',
        '$maxFrames',
        '-vsync',
        '0',
        if (vf != null && vf.isNotEmpty) ...['-vf', vf],
        '-compression_level',
        '2',
        framePattern,
      ];

      final vfParts = <String>[
        if (scaleWidth != null) 'scale=$scaleWidth:-2',
        if (videoFilter != null && videoFilter.isNotEmpty) videoFilter,
      ];
      final fullVf = vfParts.isNotEmpty ? vfParts.join(',') : null;

      var extractSession = await FFmpegKit.executeWithArguments(
        buildExtractArgs(fullVf),
      );
      var extractRc = await extractSession.getReturnCode();

      // If filter-based extraction fails, retry without color filter
      if (!ReturnCode.isSuccess(extractRc) &&
          videoFilter != null &&
          videoFilter.isNotEmpty) {
        _cleanupByPrefix(tempDir, framePrefix);
        final fallbackVf = scaleWidth != null ? 'scale=$scaleWidth:-2' : null;
        extractSession = await FFmpegKit.executeWithArguments(
          buildExtractArgs(fallbackVf),
        );
        extractRc = await extractSession.getReturnCode();
      }

      if (!ReturnCode.isSuccess(extractRc)) {
        final logs = await extractSession.getAllLogsAsString();
        throw Exception(
          'Frame extraction failed (${extractRc?.getValue()})\n$logs',
        );
      }

      // Collect extracted frames.
      final frames =
          tempDir.listSync().whereType<File>().where((f) {
              final name = f.path.split('/').last;
              return name.startsWith(framePrefix) && name.endsWith('.png');
            }).toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      if (frames.isEmpty) {
        final logs = await extractSession.getAllLogsAsString() ?? '';
        throw Exception(
          'Frame extraction produced 0 files.\n'
          'rc: ${extractRc?.getValue()}, pattern: $framePattern\n'
          '${logs.length > 500 ? logs.substring(logs.length - 500) : logs}',
        );
      }

      // Extremely short sources can decode to a single frame. Duplicate it so
      // the encoded cycle has a valid temporal span across devices.
      if (frames.length == 1) {
        final dup = File('${tempDir.path}/$framePrefix${'00002'}.png');
        await frames.first.copy(dup.path);
        frames.add(dup);
      }

      // Step 2: build forward + reverse sequence.
      int seqIndex = 1;
      String seqName(int i) => '$seqPrefix${i.toString().padLeft(5, '0')}.png';

      for (final f in frames) {
        await f.copy('${tempDir.path}/${seqName(seqIndex++)}');
      }
      for (int i = frames.length - 2; i >= 0; i--) {
        await frames[i].copy('${tempDir.path}/${seqName(seqIndex++)}');
      }

      // Step 3: encode image sequence → video.
      final outPath = await _tmpPath('cycle', 'mp4');
      final tunedBaseFps = frames.length / segmentSeconds;
      final effectiveFps = (tunedBaseFps * (speed <= 0 ? 1.0 : speed)).clamp(
        12.0,
        60.0,
      );
      final sourceStats = await _probeVideoStats(inputPath);
      final inferredWidth = scaleWidth ?? sourceStats.width;
      final inferredHeight =
          scaleWidth != null
              ? (sourceStats.height * scaleWidth / sourceStats.width).round()
              : sourceStats.height;
      final tuning = _tuningFor(
        width: inferredWidth,
        height: inferredHeight,
        fps: effectiveFps,
        favorQuality: favorQuality,
      );
      final fpsStr = effectiveFps.toStringAsFixed(2);
      final seqPattern = '${tempDir.path}/$seqPrefix%05d.png';

      String? lastLogs;
      for (final enc in _encoderCandidates(
        tuning: tuning.copyWith(fps: effectiveFps),
        favorQuality: favorQuality,
      )) {
        final encSession = await FFmpegKit.executeWithArguments([
          '-y',
          '-framerate',
          fpsStr,
          '-i',
          seqPattern,
          '-vf',
          'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
          '-an',
          ...enc,
          '-movflags',
          '+faststart',
          outPath,
        ]);
        if (ReturnCode.isSuccess(await encSession.getReturnCode()) &&
            await _hasVideoContent(outPath)) {
          await _logOutputStats(label: 'boomerang_cycle', path: outPath);
          return outPath;
        }
        lastLogs = await encSession.getAllLogsAsString();
      }

      final fallback = await _buildBoomerangViaFilterGraph(
        inputPath,
        segmentSeconds: segmentSeconds,
        speed: speed,
        scaleWidth: scaleWidth,
        targetFps: targetFps,
        videoFilter: videoFilter,
        favorQuality: favorQuality,
      );
      if (fallback != null) return fallback;

      throw Exception('Image sequence encoding failed.\n$lastLogs');
    } finally {
      _cleanupByPrefix(tempDir, framePrefix);
      _cleanupByPrefix(tempDir, seqPrefix);
    }
  }

  Future<String?> _buildBoomerangViaFilterGraph(
    String inputPath, {
    required double segmentSeconds,
    required double speed,
    required int? scaleWidth,
    required int targetFps,
    required String? videoFilter,
    required bool favorQuality,
  }) async {
    final outPath = await _tmpPath('cycle_fallback', 'mp4');
    final sourceStats = await _probeVideoStats(inputPath);
    final inferredWidth = scaleWidth ?? sourceStats.width;
    final inferredHeight =
        scaleWidth != null
            ? (sourceStats.height * scaleWidth / sourceStats.width).round()
            : sourceStats.height;
    final tunedFps = targetFps.clamp(12, 60).toDouble();
    final tuning = _tuningFor(
      width: inferredWidth,
      height: inferredHeight,
      fps: tunedFps,
      favorQuality: favorQuality,
    );

    final trimSeconds = segmentSeconds <= 0 ? 0.3 : segmentSeconds;
    final playbackRate = speed <= 0 ? 1.0 : speed;
    final speedExpr = (1.0 / playbackRate).toStringAsFixed(6);

    final vfParts = <String>[
      'trim=0:${trimSeconds.toStringAsFixed(3)}',
      'setpts=PTS-STARTPTS',
      if ((playbackRate - 1.0).abs() > 0.001) 'setpts=$speedExpr*PTS',
      if (videoFilter != null && videoFilter.isNotEmpty) videoFilter,
      if (scaleWidth != null) 'scale=$scaleWidth:-2',
      'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      'fps=${tunedFps.toStringAsFixed(2)}',
      'format=yuv420p',
    ];
    final base = vfParts.join(',');
    final filterGraph =
        '[0:v]$base[vbase];'
        '[vbase]split[vf][vb];'
        '[vb]reverse[vr];'
        '[vf][vr]concat=n=2:v=1:a=0[vout]';

    for (final enc in _encoderCandidates(
      tuning: tuning.copyWith(fps: tunedFps),
      favorQuality: favorQuality,
    )) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-filter_complex',
        filterGraph,
        '-map',
        '[vout]',
        '-an',
        ...enc,
        '-movflags',
        '+faststart',
        outPath,
      ]);
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await _hasVideoContent(outPath)) {
        return outPath;
      }
    }

    return null;
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

  static Future<void> _logOutputStats({
    required String label,
    required String path,
  }) async {
    try {
      final stats = await _probeVideoStats(path);
      final duration = await _probeDurationSeconds(path);
      final bitrate = await _probeBitrateKbps(path);
      final sizeBytes = await File(path).length();
      log(
        '$label => ${stats.width}x${stats.height} @ ${stats.fps.toStringAsFixed(2)}fps, '
        'duration=${duration?.toStringAsFixed(2) ?? 'n/a'}s, '
        'bitrate=${bitrate?.toStringAsFixed(0) ?? 'n/a'}kb/s, '
        'size=${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB, path=$path',
        name: _logName,
      );
    } catch (_) {
      // Diagnostics only.
    }
  }
}

class _VideoStats {
  const _VideoStats({
    required this.width,
    required this.height,
    required this.fps,
  });

  final int width;
  final int height;
  final double fps;
}

class _EncodeTuning {
  const _EncodeTuning({
    required this.targetBitrate,
    required this.maxBitrate,
    required this.bufferSize,
    required this.crf,
    required this.gop,
    required this.minKeyint,
    required this.fps,
  });

  final String targetBitrate;
  final String maxBitrate;
  final String bufferSize;
  final int crf;
  final int gop;
  final int minKeyint;
  final double fps;

  String get fpsString => fps.toStringAsFixed(2);

  _EncodeTuning copyWith({double? fps}) {
    return _EncodeTuning(
      targetBitrate: targetBitrate,
      maxBitrate: maxBitrate,
      bufferSize: bufferSize,
      crf: crf,
      gop: gop,
      minKeyint: minKeyint,
      fps: fps ?? this.fps,
    );
  }
}

Future<_VideoStats> _probeVideoStats(String inputPath) async {
  final session = await FFmpegKit.executeWithArguments([
    '-hide_banner',
    '-i',
    inputPath,
    '-f',
    'null',
    '-',
  ]);
  final logs = (await session.getAllLogsAsString()) ?? '';

  final dims = RegExp(r'(\d{2,5})x(\d{2,5})').firstMatch(logs);
  final fpsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*fps').firstMatch(logs);

  final width = int.tryParse(dims?.group(1) ?? '') ?? 1280;
  final height = int.tryParse(dims?.group(2) ?? '') ?? 720;
  final fps = double.tryParse(fpsMatch?.group(1) ?? '') ?? 30.0;

  return _VideoStats(
    width: width <= 0 ? 1280 : width,
    height: height <= 0 ? 720 : height,
    fps: fps <= 0 ? 30.0 : fps,
  );
}

Future<double?> _probeDurationSeconds(String inputPath) async {
  final session = await FFmpegKit.executeWithArguments([
    '-hide_banner',
    '-i',
    inputPath,
    '-f',
    'null',
    '-',
  ]);
  final logs = (await session.getAllLogsAsString()) ?? '';
  final match = RegExp(
    r'Duration:\s*(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)',
  ).firstMatch(logs);
  if (match == null) return null;

  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = double.tryParse(match.group(3) ?? '');
  if (seconds == null) return null;
  return (hours * 3600) + (minutes * 60) + seconds;
}

Future<double?> _probeBitrateKbps(String inputPath) async {
  final session = await FFmpegKit.executeWithArguments([
    '-hide_banner',
    '-i',
    inputPath,
    '-f',
    'null',
    '-',
  ]);
  final logs = (await session.getAllLogsAsString()) ?? '';
  final match = RegExp(r'bitrate:\s*(\d+(?:\.\d+)?)\s*kb/s').firstMatch(logs);
  return double.tryParse(match?.group(1) ?? '');
}

int _adaptivePosterWidth(int sourceWidth, {int maxWidth = 1600}) {
  final safeSource = sourceWidth <= 0 ? 1280 : sourceWidth;
  final clampedMax = maxWidth.clamp(720, 2160);
  final upscaled = (safeSource * 0.9).round();
  return upscaled.clamp(720, clampedMax);
}

_EncodeTuning _tuningFor({
  required int width,
  required int height,
  required double fps,
  required bool favorQuality,
}) {
  final safeW = width <= 0 ? 1280 : width;
  final safeH = height <= 0 ? 720 : height;
  final safeFps = fps <= 0 ? 30.0 : fps;
  final pixels = safeW * safeH;
  final fpsFactor = (safeFps / 30.0).clamp(0.85, 2.0);

  double baseMbps;
  if (pixels <= 640 * 360) {
    baseMbps = 2.0;
  } else if (pixels <= 854 * 480) {
    baseMbps = 3.0;
  } else if (pixels <= 1280 * 720) {
    baseMbps = 5.8;
  } else if (pixels <= 1920 * 1080) {
    baseMbps = 9.0;
  } else if (pixels <= 2560 * 1440) {
    baseMbps = 13.5;
  } else {
    baseMbps = 18.0;
  }

  var targetMbps = baseMbps * fpsFactor;
  if (favorQuality) {
    targetMbps = targetMbps.clamp(2.8, 24.0);
  } else {
    targetMbps = targetMbps.clamp(1.6, 9.0);
  }
  final maxMbps = (targetMbps * 1.45).clamp(3.4, 28.0);
  final bufMbps = (maxMbps * 2).clamp(7.0, 48.0);

  final crf =
      pixels <= 854 * 480
          ? 19
          : pixels <= 1280 * 720
          ? 18
          : pixels <= 1920 * 1080
          ? 17
          : 16;
  final gop = (safeFps * 2).round().clamp(24, 180);

  String fmt(double mbps) => '${mbps.toStringAsFixed(1)}M';

  return _EncodeTuning(
    targetBitrate: fmt(targetMbps),
    maxBitrate: fmt(maxMbps),
    bufferSize: fmt(bufMbps),
    crf: favorQuality ? crf - 1 : crf,
    gop: gop,
    minKeyint: (gop / 2).round().clamp(12, 90),
    fps: safeFps,
  );
}
