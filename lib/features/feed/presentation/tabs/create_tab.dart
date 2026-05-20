import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/feed/infrastructure/gallery_video_ingestor.dart';
import 'package:boomerang/features/feed/presentation/editor/boomerang_editor_page.dart';
import 'package:boomerang/features/feed/presentation/editor/video_trim_page.dart';
import 'package:boomerang/features/feed/presentation/camera/boomerang_camera_page.dart';

class CreateTab extends ConsumerStatefulWidget {
  const CreateTab({super.key});

  static const String routeName = '/create_tab';

  @override
  ConsumerState<CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends ConsumerState<CreateTab> {
  bool _isProcessing = false;

  Future<void> _openCamera() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BoomerangCameraPage()));
  }

  // Max window the user can pick from a gallery clip — matches the existing
  // boomerang segment budget (1.5 s → 3 s looped).
  static const _maxWindow = Duration(milliseconds: 1500);

  Future<void> _importFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final picker = ImagePicker();
      // No maxDuration on the picker any more — the user trims it themselves.
      final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;

      final ingested = await GalleryVideoIngestor().ingest(file);
      if (!mounted) return;

      // Videos already within the allowed window skip the trim page.
      final sourceDuration = ingested.duration;
      if (sourceDuration <= _maxWindow) {
        final trimmed = await const BoomerangProcessor().trimToMaxDuration(
          ingested.file.path,
          maxSeconds: 1.5,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BoomerangEditorPage(inputFile: File(trimmed)),
          ),
        );
        return;
      }

      // Long clip → let the user pick which slice to use.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => VideoTrimPage(
                inputFile: ingested.file,
                maxWindow: _maxWindow,
              ),
        ),
      );
    } on GalleryVideoIngestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Create',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Record a quick clip or import from your gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _openCamera,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(_isProcessing ? 'Processing…' : 'Record video'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _importFromGallery,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(_isProcessing ? 'Processing…' : 'Import video'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
