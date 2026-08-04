import 'dart:io';

import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class GalleryVideoIngestException implements Exception {
  const GalleryVideoIngestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GalleryVideoIngestResult {
  const GalleryVideoIngestResult({required this.file, required this.duration});

  final File file;
  final Duration duration;
}

class GalleryVideoIngestor {
  GalleryVideoIngestor({BoomerangProcessor? processor})
    : _processor = processor ?? const BoomerangProcessor();

  static const int _maxBytes = 500 * 1024 * 1024;
  static const Duration _minDuration = Duration(milliseconds: 250);

  final BoomerangProcessor _processor;

  Future<GalleryVideoIngestResult> ingest(XFile source) async {
    final localSource = await _materializeSource(source);
    await _validateFile(localSource);
    final sourceDuration = await _probeDuration(localSource.path);
    _validateDuration(sourceDuration);

    final normalizedPath = await _processor.transcodeToSafeMp4(
      localSource.path,
    );
    final normalizedFile = File(normalizedPath);
    await _validateFile(normalizedFile);
    final normalizedDuration = await _probeDuration(normalizedPath);
    _validateDuration(normalizedDuration);

    return GalleryVideoIngestResult(
      file: normalizedFile,
      duration: normalizedDuration,
    );
  }

  Future<File> _materializeSource(XFile source) async {
    final rawPath = source.path.trim();
    if (rawPath.isEmpty) {
      throw const GalleryVideoIngestException(
        'Could not read that video. Please pick a different file.',
      );
    }

    var candidatePath = rawPath;
    if (rawPath.startsWith('file://')) {
      try {
        candidatePath = Uri.parse(rawPath).toFilePath();
      } catch (_) {}
    }

    final candidate = File(candidatePath);
    if (!rawPath.startsWith('content://') &&
        !rawPath.startsWith('ph://') &&
        await candidate.exists() &&
        await candidate.length() > 0) {
      return candidate;
    }

    // Stream content:// (common on Android) instead of readAsBytes — loading
    // up to 500MB into the Dart/Java heap OOMs mid-tier devices.
    final ext = _extensionFrom(source.name, rawPath);
    final tmp = await getTemporaryDirectory();
    final output = File(
      '${tmp.path}/gallery_import_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    final sink = output.openWrite();
    var total = 0;
    try {
      await for (final chunk in source.openRead()) {
        total += chunk.length;
        if (total > _maxBytes) {
          throw const GalleryVideoIngestException(
            'This video is too large to process. Please choose a smaller clip.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      if (e is GalleryVideoIngestException) rethrow;
      throw const GalleryVideoIngestException(
        'Could not read that video file. Please re-download it and try again.',
      );
    }

    if (total <= 0 || !await output.exists()) {
      throw const GalleryVideoIngestException(
        'Could not read that video file. Please re-download it and try again.',
      );
    }
    return output;
  }

  Future<void> _validateFile(File file) async {
    if (!await file.exists()) {
      throw const GalleryVideoIngestException(
        'Could not access the selected video. Please try a different file.',
      );
    }
    final size = await file.length();
    if (size <= 0) {
      throw const GalleryVideoIngestException(
        'The selected video appears empty. Please choose another one.',
      );
    }
    if (size > _maxBytes) {
      throw const GalleryVideoIngestException(
        'This video is too large to process. Please choose a smaller clip.',
      );
    }
  }

  Future<Duration> _probeDuration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return Duration.zero;
    } finally {
      await controller.dispose();
    }
  }

  void _validateDuration(Duration duration) {
    if (duration == Duration.zero) {
      throw const GalleryVideoIngestException(
        'Unsupported or corrupted video format. Please choose a different clip.',
      );
    }
    if (duration < _minDuration) {
      throw const GalleryVideoIngestException(
        'Video is too short. Please choose one at least 0.3 seconds long.',
      );
    }
  }

  String _extensionFrom(String name, String path) {
    String from(String input) {
      final cleaned = input.split('?').first.split('#').first;
      final dot = cleaned.lastIndexOf('.');
      if (dot < 0 || dot == cleaned.length - 1) return '';
      return cleaned.substring(dot + 1).toLowerCase();
    }

    final fromName = from(name);
    if (fromName.isNotEmpty) return fromName;

    final fromPath = from(path);
    if (fromPath.isNotEmpty) return fromPath;

    return 'mp4';
  }
}
