import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/feed/infrastructure/gallery_video_ingestor.dart';
import 'package:boomerang/features/feed/presentation/editor/boomerang_editor_page.dart';
import 'package:boomerang/features/feed/presentation/editor/video_trim_page.dart';

/// Max window the user can pull out of a gallery clip — matches the boomerang
/// segment budget (1.5 s → 3 s looped).
const Duration kGalleryMaxWindow = Duration(milliseconds: 1500);

/// Ingests a picked gallery [file] and routes the user onward:
///   - clips already within [maxWindow] are hard-trimmed and sent straight to
///     the [BoomerangEditorPage];
///   - longer clips go through [VideoTrimPage] so the user picks a slice.
///
/// This is the single source of truth for "what to do with a gallery video"
/// and is shared by the manual picker ([CreateTab]) and the Android lost-data
/// recovery path ([HomeShell]) so a video that survives an Activity restart is
/// handled exactly like one picked normally.
///
/// Throws [GalleryVideoIngestException] when the clip can't be ingested; the
/// caller is responsible for surfacing the message.
Future<void> presentGalleryVideo(
  BuildContext context,
  XFile file, {
  Duration maxWindow = kGalleryMaxWindow,
}) async {
  final ingested = await GalleryVideoIngestor().ingest(file);
  if (!context.mounted) return;

  if (ingested.duration <= maxWindow) {
    final trimmed = await const BoomerangProcessor().trimToMaxDuration(
      ingested.file.path,
      maxSeconds: maxWindow.inMilliseconds / 1000.0,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoomerangEditorPage(inputFile: File(trimmed)),
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoTrimPage(inputFile: ingested.file, maxWindow: maxWindow),
    ),
  );
}
