import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/features/feed/presentation/editor/boomerang_editor_page.dart';

class CreateTab extends ConsumerStatefulWidget {
  const CreateTab({super.key});

  static const String routeName = '/create_tab';

  @override
  ConsumerState<CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends ConsumerState<CreateTab> {
  bool _isProcessing = false;

  Future<File?> _pickVideoFrom(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickVideo(source: source);
    if (file == null) return null;
    return File(file.path);
  }

  // Upload moved to editor page

  Future<void> _onCreate(ImageSource source) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final input = await _pickVideoFrom(source);
      if (input == null) return;

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BoomerangEditorPage(inputFile: input),
        ),
      );
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
                    onPressed:
                        _isProcessing
                            ? null
                            : () => _onCreate(ImageSource.camera),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(_isProcessing ? 'Processing…' : 'Record video'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isProcessing
                            ? null
                            : () => _onCreate(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
