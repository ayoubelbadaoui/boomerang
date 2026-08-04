import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';

import 'package:boomerang/core/storage/storage_metadata.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

enum UploadPhase { idle, processing, uploading, finalizing, done, failed }

class UploadState {
  const UploadState({
    this.phase = UploadPhase.idle,
    this.progress,
    this.errorMessage,
    this.localPosterPath,
  });

  final UploadPhase phase;
  final double? progress;
  final String? errorMessage;
  final String? localPosterPath;

  bool get isActive =>
      phase == UploadPhase.processing ||
      phase == UploadPhase.uploading ||
      phase == UploadPhase.finalizing;

  UploadState copyWith({
    UploadPhase? phase,
    double? Function()? progress,
    String? Function()? errorMessage,
    String? Function()? localPosterPath,
  }) {
    return UploadState(
      phase: phase ?? this.phase,
      progress: progress != null ? progress() : this.progress,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      localPosterPath:
          localPosterPath != null ? localPosterPath() : this.localPosterPath,
    );
  }

  static const idle = UploadState();
}

class _PublishArgs {
  const _PublishArgs({
    required this.inputFile,
    required this.mirrorVideo,
    required this.segmentSeconds,
    required this.speed,
    required this.colorFilter,
    required this.caption,
  });
  final File inputFile;
  final bool mirrorVideo;
  final double segmentSeconds;
  final double speed;
  final String? colorFilter;
  final String caption;
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);

class UploadController extends Notifier<UploadState> {
  _PublishArgs? _lastArgs;
  static const _logName = 'BoomerangRepo';
  static const _uploadPosterMaxWidth = 2000;
  static const _uploadPosterJpegQuality = 2;

  @override
  UploadState build() => UploadState.idle;

  void dismiss() => state = UploadState.idle;

  Future<void> retry() async {
    if (_lastArgs == null) return;
    final args = _lastArgs!;
    log(
      'Retrying failed upload for file: ${args.inputFile.path}',
      name: _logName,
    );
    await publish(
      inputFile: args.inputFile,
      mirrorVideo: args.mirrorVideo,
      segmentSeconds: args.segmentSeconds,
      speed: args.speed,
      colorFilter: args.colorFilter,
      caption: args.caption,
    );
  }

  Future<void> publish({
    required File inputFile,
    required bool mirrorVideo,
    required double segmentSeconds,
    required double speed,
    required String? colorFilter,
    required String caption,
  }) async {
    if (state.isActive) {
      log(
        'publish() ignored because upload is already active. phase=${state.phase}',
        name: _logName,
      );
      return;
    }

    final args = _PublishArgs(
      inputFile: inputFile,
      mirrorVideo: mirrorVideo,
      segmentSeconds: segmentSeconds,
      speed: speed,
      colorFilter: colorFilter,
      caption: caption,
    );
    _lastArgs = args;
    log(
      'Starting publish. file=${inputFile.path}, mirror=$mirrorVideo, '
      'segmentSeconds=$segmentSeconds, speed=$speed, hasFilter=${colorFilter != null}',
      name: _logName,
    );

    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) {
      log('publish() aborted: current user profile is null', name: _logName);
      state = const UploadState(
        phase: UploadPhase.failed,
        errorMessage: 'Please log in first.',
      );
      return;
    }

    try {
      await _run(args, me);
    } catch (e, st) {
      log('Upload failed', name: _logName, error: e, stackTrace: st);
      state = UploadState(
        phase: UploadPhase.failed,
        errorMessage: _friendlyError(e),
      );
    }
  }

  static String _friendlyError(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'storage/retry-limit-exceeded' || 'storage/server-file-wrong-size' =>
          'Upload interrupted. Please try again.',
        'storage/unauthenticated' => 'Please log in and try again.',
        'storage/unauthorized' => 'Permission denied. Please log in again.',
        'storage/quota-exceeded' => 'Storage full. Please try again later.',
        'storage/canceled' => 'Upload was cancelled.',
        _ => 'Upload failed. Please try again.',
      };
    }

    final msg = error.toString().toLowerCase();

    if (error is SocketException || msg.contains('socketexception')) {
      return 'No internet connection. Please try again.';
    }
    if (msg.contains('permission') ||
        msg.contains('unauthorized') ||
        msg.contains('403')) {
      return 'Permission denied. Please log in again.';
    }
    if (msg.contains('not found') || msg.contains('404')) {
      return 'Something went wrong. Please try again.';
    }
    if (msg.contains('quota') || msg.contains('resource_exhausted')) {
      return 'Service is busy. Please try again later.';
    }
    if (msg.contains('timeout') || msg.contains('deadline')) {
      return 'Upload timed out. Check your connection.';
    }
    if (msg.contains('input file does not exist')) {
      return 'Video file not found. Please record again.';
    }
    if (msg.contains('frame extraction') || msg.contains('poster generation')) {
      return 'Could not process video. Try a different clip.';
    }
    if (msg.contains('unsupported or corrupted video format')) {
      return 'Unsupported video format. Please pick a different file.';
    }
    if (msg.contains('safe transcode failed')) {
      return 'This video format is not supported yet. Please try another clip.';
    }
    if (msg.contains('could not access the selected video')) {
      return 'Could not access the selected video. Please re-pick it.';
    }
    if (msg.contains('too large to process')) {
      return 'Video is too large to process. Please choose a smaller clip.';
    }
    if (msg.contains('too short')) {
      return 'Video is too short. Please choose one at least 0.3 seconds long.';
    }
    if (msg.contains('encoding failed') || msg.contains('ffmpeg')) {
      return 'Video processing failed. Try a different clip.';
    }
    if (msg.contains('canceled') || msg.contains('cancelled')) {
      return 'Upload was cancelled.';
    }

    return 'Upload failed. Please try again.';
  }

  Future<void> _run(_PublishArgs args, UserProfile me) async {
    final processor = ref.read(boomerangProcessorProvider);
    final storage = ref.read(storageProvider);
    final repo = ref.read(boomerangRepoProvider);
    final totalTimer = Stopwatch()..start();

    // --- Phase 1: Processing (FFmpeg) ---
    final processingTimer = Stopwatch()..start();
    log('Phase=processing start', name: _logName);
    state = const UploadState(phase: UploadPhase.processing);

    final exists = await args.inputFile.exists();
    if (!exists || await args.inputFile.length() <= 0) {
      log(
        'Input file missing or empty: ${args.inputFile.path}',
        name: _logName,
      );
      throw Exception('Input file does not exist: ${args.inputFile.path}');
    }

    String inputPath = args.inputFile.path;
    if (args.mirrorVideo) {
      log('Mirroring input video before processing', name: _logName);
      inputPath = await processor.mirrorInput(inputPath);
    }

    log('Building boomerang with FFmpeg. input=$inputPath', name: _logName);
    final outPath = await processor.makeBoomerang(
      inputPath,
      segmentSeconds: args.segmentSeconds,
      totalDurationSeconds: 6.0,
      speed: args.speed,
      videoFilter: args.colorFilter,
    );
    final videoMetadata = await _probeVideoMetadata(outPath);
    try {
      final outBytes = await File(outPath).length();
      log(
        'Processed boomerang ready. path=$outPath, sizeMB=${(outBytes / (1024 * 1024)).toStringAsFixed(2)}',
        name: _logName,
      );
    } catch (_) {}

    // Generate poster once and reuse it for both preview and upload to reduce
    // end-to-end publish latency.
    String? localPoster;
    try {
      localPoster = await processor.generatePoster(
        inputPath,
        maxWidth: _uploadPosterMaxWidth,
        jpegQuality: _uploadPosterJpegQuality,
        videoFilter: args.colorFilter,
      );
    } catch (e, st) {
      log(
        'Non-fatal: failed to generate local poster preview',
        name: _logName,
        error: e,
        stackTrace: st,
      );
    }
    processingTimer.stop();
    log(
      'Phase=processing done in ${processingTimer.elapsedMilliseconds}ms',
      name: _logName,
    );

    // --- Phase 2: Uploading (video + poster in parallel) ---
    final uploadTimer = Stopwatch()..start();
    log('Phase=uploading start. output=$outPath', name: _logName);
    state = UploadState(
      phase: UploadPhase.uploading,
      progress: 0.0,
      localPosterPath: localPoster,
    );

    final videoFuture = _uploadVideo(storage, outPath);
    final posterFuture = _uploadPoster(
      storage,
      processor,
      inputPath,
      args.colorFilter,
      preferredPosterPath: localPoster,
      fallbackVideoPath: outPath,
    );

    final results = await Future.wait([videoFuture, posterFuture]);
    final videoUrl = results[0]!;
    final posterUrl = results[1];
    log(
      'Upload complete. videoUrlReady=${videoUrl.isNotEmpty}, '
      'posterUrlReady=${posterUrl != null && posterUrl.isNotEmpty}',
      name: _logName,
    );
    uploadTimer.stop();
    log(
      'Phase=uploading done in ${uploadTimer.elapsedMilliseconds}ms',
      name: _logName,
    );

    // --- Phase 3: Finalizing (Firestore write) ---
    final finalizeTimer = Stopwatch()..start();
    log('Phase=finalizing start. writing Firestore post', name: _logName);
    state = state.copyWith(phase: UploadPhase.finalizing, progress: () => null);

    final tags = _parseHashtags(args.caption);

    await repo.createBoomerangPost(
      userId: me.uid,
      userName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
      userAvatar: me.avatarUrl,
      videoUrl: videoUrl,
      imageUrl: posterUrl,
      caption: args.caption.isEmpty ? null : args.caption,
      hashtags: tags.isEmpty ? null : tags.toList(),
      ownerIsPrivate: me.isPrivate,
      videoWidth: videoMetadata?.width,
      videoHeight: videoMetadata?.height,
      videoAspectRatio: videoMetadata?.aspectRatio,
      videoDurationMs: videoMetadata?.durationMs,
    );
    log('Firestore boomerang post created successfully', name: _logName);
    finalizeTimer.stop();
    log(
      'Phase=finalizing done in ${finalizeTimer.elapsedMilliseconds}ms',
      name: _logName,
    );

    // --- Phase 4: Done ---
    state = state.copyWith(phase: UploadPhase.done);
    totalTimer.stop();
    log(
      'Phase=done. totalPublishMs=${totalTimer.elapsedMilliseconds}',
      name: _logName,
    );

    // Auto-refresh profile grid so the new post appears immediately
    try {
      await ref.read(userBoomerangsControllerProvider.notifier).refresh();
    } catch (e, st) {
      log(
        'Non-fatal: failed to refresh user boomerangs after upload',
        name: _logName,
        error: e,
        stackTrace: st,
      );
    }

    _lastArgs = null;
  }

  Future<String?> _uploadVideo(FirebaseStorage storage, String filePath) async {
    final storagePath =
        'boomerangs/${DateTime.now().millisecondsSinceEpoch}.mp4';
    log(
      'Uploading video to Firebase Storage path=$storagePath',
      name: _logName,
    );
    final task = storage
        .ref(storagePath)
        .putFile(File(filePath), immutableMediaMetadata('video/mp4'));

    task.snapshotEvents.listen(
      (snap) {
        if (state.phase != UploadPhase.uploading) return;
        final total = snap.totalBytes;
        if (total > 0) {
          state = state.copyWith(progress: () => snap.bytesTransferred / total);
        }
      },
      onError: (Object e, StackTrace st) {
        log(
          'Video snapshot stream error',
          name: _logName,
          error: e,
          stackTrace: st,
        );
      },
    );

    final snapshot = await task;
    final url = await snapshot.ref.getDownloadURL();
    log('Video upload finished for path=$storagePath', name: _logName);
    return url;
  }

  Future<String?> _uploadPoster(
    FirebaseStorage storage,
    BoomerangProcessor processor,
    String inputPath,
    String? colorFilter, {
    String? preferredPosterPath,
    String? fallbackVideoPath,
  }) async {
    try {
      String? posterPath = preferredPosterPath;

      if (posterPath == null || !await File(posterPath).exists()) {
        try {
          log('Generating poster from input video for upload', name: _logName);
          posterPath = await processor.generatePoster(
            inputPath,
            maxWidth: _uploadPosterMaxWidth,
            jpegQuality: _uploadPosterJpegQuality,
            videoFilter: colorFilter,
          );
        } catch (e, st) {
          log(
            'Primary poster generation failed; trying fallback video',
            name: _logName,
            error: e,
            stackTrace: st,
          );
          if (fallbackVideoPath != null) {
            posterPath = await processor.generatePoster(
              fallbackVideoPath,
              maxWidth: _uploadPosterMaxWidth,
              jpegQuality: _uploadPosterJpegQuality,
            );
          }
        }
      }
      if (posterPath == null) {
        log('Skipping poster upload: no poster path available', name: _logName);
        return null;
      }
      try {
        final posterBytes = await File(posterPath).length();
        log(
          'Poster ready for upload. path=$posterPath, sizeKB=${(posterBytes / 1024).toStringAsFixed(1)}',
          name: _logName,
        );
      } catch (_) {}
      final posterRef = storage.ref(
        'boomerangs/posters/poster_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      log('Uploading poster to Firebase Storage', name: _logName);
      final posterTask = await posterRef.putFile(
        File(posterPath),
        immutableMediaMetadata('image/jpeg'),
      );
      final url = await posterTask.ref.getDownloadURL();
      log('Poster upload finished', name: _logName);
      return url;
    } catch (e, st) {
      log(
        'Non-fatal: poster upload failed',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  static List<String> _parseHashtags(String caption) {
    final tags = <String>{};
    final re = RegExp(r'(?:#)([A-Za-z0-9_]{1,30})');
    for (final m in re.allMatches(caption)) {
      final t = m.group(1);
      if (t != null && t.isNotEmpty) tags.add(t.toLowerCase());
    }
    return tags.toList();
  }

  Future<_VideoMetadata?> _probeVideoMetadata(String filePath) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(filePath));
      await controller.initialize();
      final value = controller.value;
      final width = value.size.width.round();
      final height = value.size.height.round();
      final durationMs = value.duration.inMilliseconds;
      if (width <= 0 || height <= 0 || durationMs <= 0) return null;
      final aspectRatio = value.aspectRatio;
      return _VideoMetadata(
        width: width,
        height: height,
        aspectRatio: aspectRatio > 0 ? aspectRatio : (width / height),
        durationMs: durationMs,
      );
    } catch (e, st) {
      log(
        'Non-fatal: could not probe processed video metadata',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      return null;
    } finally {
      await controller?.dispose();
    }
  }
}

class _VideoMetadata {
  const _VideoMetadata({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.durationMs,
  });

  final int width;
  final int height;
  final double aspectRatio;
  final int durationMs;
}
