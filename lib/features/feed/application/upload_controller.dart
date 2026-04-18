import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';

import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  UploadState build() => UploadState.idle;

  void dismiss() => state = UploadState.idle;

  Future<void> retry() async {
    if (_lastArgs == null) return;
    final args = _lastArgs!;
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
    if (state.isActive) return;

    final args = _PublishArgs(
      inputFile: inputFile,
      mirrorVideo: mirrorVideo,
      segmentSeconds: segmentSeconds,
      speed: speed,
      colorFilter: colorFilter,
      caption: caption,
    );
    _lastArgs = args;

    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) {
      state = const UploadState(
        phase: UploadPhase.failed,
        errorMessage: 'Please log in first.',
      );
      return;
    }

    try {
      await _run(args, me);
    } catch (e, st) {
      log('Upload failed', name: 'UploadController', error: e, stackTrace: st);
      state = UploadState(
        phase: UploadPhase.failed,
        errorMessage: '$e',
      );
    }
  }

  Future<void> _run(_PublishArgs args, UserProfile me) async {
    final processor = ref.read(boomerangProcessorProvider);
    final storage = ref.read(storageProvider);
    final repo = ref.read(boomerangRepoProvider);

    // --- Phase 1: Processing (FFmpeg) ---
    state = const UploadState(phase: UploadPhase.processing);

    String inputPath = args.inputFile.path;
    if (args.mirrorVideo) {
      inputPath = await processor.mirrorInput(inputPath);
    }

    final outPath = await processor.makeBoomerang(
      inputPath,
      segmentSeconds: args.segmentSeconds,
      totalDurationSeconds: 6.0,
      speed: args.speed,
      videoFilter: args.colorFilter,
    );

    // Generate a local poster early for the progress bar thumbnail
    String? localPoster;
    try {
      localPoster = await processor.generatePoster(
        inputPath,
        targetWidth: 480,
        videoFilter: args.colorFilter,
      );
    } catch (_) {}

    // --- Phase 2: Uploading (video + poster in parallel) ---
    state = UploadState(
      phase: UploadPhase.uploading,
      progress: 0.0,
      localPosterPath: localPoster,
    );

    final videoFuture = _uploadVideo(storage, outPath);
    final posterFuture = _uploadPoster(storage, processor, inputPath, args.colorFilter);

    final results = await Future.wait([videoFuture, posterFuture]);
    final videoUrl = results[0]!;
    final posterUrl = results[1];

    // --- Phase 3: Finalizing (Firestore write) ---
    state = state.copyWith(
      phase: UploadPhase.finalizing,
      progress: () => null,
    );

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
    );

    // --- Phase 4: Done ---
    state = state.copyWith(phase: UploadPhase.done);

    // Auto-refresh profile grid so the new post appears immediately
    try {
      await ref.read(userBoomerangsControllerProvider.notifier).refresh();
    } catch (_) {}

    _lastArgs = null;
  }

  Future<String?> _uploadVideo(FirebaseStorage storage, String filePath) async {
    final storagePath =
        'boomerangs/${DateTime.now().millisecondsSinceEpoch}.mp4';
    final task = storage.ref(storagePath).putFile(File(filePath));

    task.snapshotEvents.listen((snap) {
      if (state.phase != UploadPhase.uploading) return;
      final total = snap.totalBytes;
      if (total > 0) {
        state = state.copyWith(
          progress: () => snap.bytesTransferred / total,
        );
      }
    });

    final snapshot = await task;
    return snapshot.ref.getDownloadURL();
  }

  Future<String?> _uploadPoster(
    FirebaseStorage storage,
    BoomerangProcessor processor,
    String inputPath,
    String? colorFilter,
  ) async {
    try {
      final posterPath = await processor.generatePoster(
        inputPath,
        videoFilter: colorFilter,
      );
      final posterRef = storage.ref(
        'boomerangs/posters/poster_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final posterTask = await posterRef.putFile(File(posterPath));
      return posterTask.ref.getDownloadURL();
    } catch (_) {
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
}
