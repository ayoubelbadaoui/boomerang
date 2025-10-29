import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/infrastructure/providers.dart';

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

  Future<String> _uploadToStorage(File file) async {
    final storage = ref.read(storageProvider);
    final String path =
        'boomerangs/${DateTime.now().millisecondsSinceEpoch}.mp4';
    final task = await storage.ref(path).putFile(file);
    return await task.ref.getDownloadURL();
  }

  Future<void> _onCreate(ImageSource source) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final input = await _pickVideoFrom(source);
      if (input == null) return;

      // iOS Simulator guard: FFmpeg can be problematic on some setups; try/catch
      final processor = ref.read(boomerangProcessorProvider);
      final String outPath = await processor.makeBoomerang(input.path);
      final outFile = File(outPath);

      final url = await _uploadToStorage(outFile);

      final me = ref.read(currentUserProfileProvider).value;
      if (me == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
        return;
      }
      await ref
          .read(boomerangRepoProvider)
          .createBoomerangPost(
            userId: me.uid,
            userName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
            userAvatar: me.avatarUrl,
            videoUrl: url,
            imageUrl: null,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Boomerang created')));
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed:
                    _isProcessing ? null : () => _onCreate(ImageSource.camera),
                icon: const Icon(Icons.videocam_outlined),
                label: Text(_isProcessing ? 'Processing…' : 'Record video'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed:
                    _isProcessing ? null : () => _onCreate(ImageSource.gallery),
                icon: const Icon(Icons.video_library_outlined),
                label: Text(_isProcessing ? 'Processing…' : 'Import video'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Pick a video, create forward+reverse, upload & post'),
        ],
      ),
    );
  }
}
