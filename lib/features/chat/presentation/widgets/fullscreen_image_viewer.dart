import 'package:boomerang/core/utils/immersive_system_ui.dart';
import 'package:boomerang/features/chat/presentation/widgets/chat_image_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenImageViewer extends StatefulWidget {
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
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder:
            (_, __, ___) =>
                FullscreenImageViewer(imageUrl: imageUrl, heroTag: heroTag),
        transitionsBuilder: (_, animation, __, child) {
          final opacity = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );
          return FadeTransition(opacity: opacity, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  @override
  void initState() {
    super.initState();
    ImmersiveSystemUi.enter();
  }

  @override
  void dispose() {
    ImmersiveSystemUi.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final imageProvider = resolveChatImageProvider(widget.imageUrl);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag,
                createRectTween:
                    (begin, end) => MaterialRectArcTween(begin: begin, end: end),
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
