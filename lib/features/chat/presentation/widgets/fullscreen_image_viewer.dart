import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:boomerang/features/chat/presentation/widgets/chat_image_renderer.dart';

class FullscreenImageViewer extends StatelessWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  final String imageUrl;
  final String heroTag;

  static void open(
    BuildContext context, {
    required String imageUrl,
    required String heroTag,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => FullscreenImageViewer(imageUrl: imageUrl, heroTag: heroTag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final imageProvider = resolveChatImageProvider(imageUrl);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child:
                  imageProvider == null
                      ? const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      )
                      : InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Image(
                          image: imageProvider,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder:
                              (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 48,
                              ),
                        ),
                      ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: padding.top + 8,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
