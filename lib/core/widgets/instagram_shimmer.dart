import 'package:flutter/material.dart';

/// Instagram-style loading placeholders (light: ~#EFEFEF bone + soft white sweep;
/// dark reel: ~#262626 bone + subtle gray lift).
///
/// Wrap a subtree with [ShimmerScope], then use [ShimmerBone] / [ShimmerCircle]
/// for each placeholder so every element gets its own masked highlight.
class InstagramShimmerColors {
  InstagramShimmerColors._();

  /// IG feed / profile skeleton fill (classic “Instagram gray”).
  static const Color lightBone = Color(0xFFEFEFEF);

  /// Page behind skeleton on white screens (IG uses near-white).
  static const Color lightCanvas = Color(0xFFFAFAFA);

  /// Dark mode / Reels-style skeleton.
  static const Color darkBone = Color(0xFF262626);

  static const Color darkCanvas = Color(0xFF000000);

  /// Sweep gradient for [Brightness.light] — soft peak toward white like IG iOS.
  static Shader sweepShaderLight(Rect bounds, double phase) {
    final shift = phase * 2.6 - 1.3;
    return LinearGradient(
      begin: Alignment(shift - 0.85, 0),
      end: Alignment(shift + 0.85, 0),
      colors: const [
        Color(0xFFEBEBEB),
        Color(0xFFEFEFEF),
        Color(0xFFF5F5F5),
        Color(0xFFFFFFFF),
        Color(0xFFF5F5F5),
        Color(0xFFEFEFEF),
        Color(0xFFEBEBEB),
      ],
      stops: const [0.0, 0.12, 0.28, 0.5, 0.72, 0.88, 1.0],
    ).createShader(bounds);
  }

  /// Sweep for dark fullscreen player.
  static Shader sweepShaderDark(Rect bounds, double phase) {
    final shift = phase * 2.6 - 1.3;
    return LinearGradient(
      begin: Alignment(shift - 0.85, 0),
      end: Alignment(shift + 0.85, 0),
      colors: const [
        Color(0xFF181818),
        Color(0xFF222222),
        Color(0xFF303030),
        Color(0xFF3D3D3D),
        Color(0xFF303030),
        Color(0xFF222222),
        Color(0xFF181818),
      ],
      stops: const [0.0, 0.12, 0.28, 0.5, 0.72, 0.88, 1.0],
    ).createShader(bounds);
  }
}

class ShimmerInherited extends InheritedWidget {
  const ShimmerInherited({
    super.key,
    required this.animation,
    required this.brightness,
    required super.child,
  });

  final Animation<double> animation;
  final Brightness brightness;

  /// Does not register a rebuild dependency (presence check only).
  static ShimmerInherited? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShimmerInherited>();

  static ShimmerInherited of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<ShimmerInherited>();
    assert(inherited != null, 'ShimmerBone must be inside ShimmerScope');
    return inherited!;
  }

  @override
  bool updateShouldNotify(ShimmerInherited oldWidget) =>
      animation != oldWidget.animation || brightness != oldWidget.brightness;
}

/// Single periodic animation shared by all bones under this scope.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({
    super.key,
    required this.child,
    this.brightness = Brightness.light,
    this.duration = const Duration(milliseconds: 1600),
  });

  final Widget child;
  final Brightness brightness;
  final Duration duration;

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant ShimmerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShimmerInherited(
      animation: _controller,
      brightness: widget.brightness,
      child: widget.child,
    );
  }
}

/// Rounded rectangle placeholder with IG-style shimmer (use inside [ShimmerScope]).
class ShimmerBone extends StatelessWidget {
  const ShimmerBone({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.phaseShift = 0.0,
  });

  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  /// Slight de-phase between siblings (0–1).
  final double phaseShift;

  @override
  Widget build(BuildContext context) {
    final inherited = ShimmerInherited.of(context);
    final isDark = inherited.brightness == Brightness.dark;
    final baseColor =
        isDark ? InstagramShimmerColors.darkBone : InstagramShimmerColors.lightBone;

    return AnimatedBuilder(
      animation: inherited.animation,
      builder: (context, _) {
        final t = (inherited.animation.value + phaseShift) % 1.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) =>
              isDark
                  ? InstagramShimmerColors.sweepShaderDark(bounds, t)
                  : InstagramShimmerColors.sweepShaderLight(bounds, t),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: borderRadius,
            ),
          ),
        );
      },
    );
  }
}

/// Circular [ShimmerBone].
class ShimmerCircle extends StatelessWidget {
  const ShimmerCircle({
    super.key,
    required this.size,
    this.phaseShift = 0.0,
  });

  final double size;
  final double phaseShift;

  @override
  Widget build(BuildContext context) {
    return ShimmerBone(
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size),
      phaseShift: phaseShift,
    );
  }
}
