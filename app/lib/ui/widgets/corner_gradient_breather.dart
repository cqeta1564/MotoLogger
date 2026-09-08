import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Animated corner gradient wash that breathes and transitions color
/// based on real-time motorcycle lean angle from IMU / BNO085.
/// 
/// Renders smooth color blends (barevný přeliv) radiating from the upper corners:
/// Green -> Yellow -> Orange -> Racing Red -> Pure White fade,
/// exactly matching the rider's telemetry proposal.
class CornerGradientBreather extends StatefulWidget {
  final double leanAngleDeg; // Negative for left, positive for right
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;

  const CornerGradientBreather({
    super.key,
    required this.leanAngleDeg,
    this.maxLeanLeftDeg = 0.0,
    this.maxLeanRightDeg = 0.0,
  });

  @override
  State<CornerGradientBreather> createState() => _CornerGradientBreatherState();
}

class _CornerGradientBreatherState extends State<CornerGradientBreather>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Smooth breathing wave from 0.0 to 1.0
        final breath = (sin(_controller.value * 2 * pi) + 1.0) / 2.0;

        final leftLean = widget.leanAngleDeg < 0 ? -widget.leanAngleDeg : 0.0;
        final rightLean = widget.leanAngleDeg > 0 ? widget.leanAngleDeg : 0.0;

        return CustomPaint(
          size: Size.infinite,
          painter: _CornerGradientPainter(
            leftLean: leftLean,
            rightLean: rightLean,
            breath: breath,
          ),
        );
      },
    );
  }
}

class _CornerGradientPainter extends CustomPainter {
  final double leftLean;
  final double rightLean;
  final double breath;

  _CornerGradientPainter({
    required this.leftLean,
    required this.rightLean,
    required this.breath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final isLandscape = w > h;

    // 1. LEFT CORNER GRADIENT (Green -> Yellow -> Orange -> Red)
    _drawCorner(
      canvas: canvas,
      size: size,
      isLeft: true,
      leanDeg: leftLean,
      oppositeLeanDeg: rightLean,
      isLandscape: isLandscape,
    );

    // 2. RIGHT CORNER GRADIENT (Green -> Yellow -> Orange -> Red)
    _drawCorner(
      canvas: canvas,
      size: size,
      isLeft: false,
      leanDeg: rightLean,
      oppositeLeanDeg: leftLean,
      isLandscape: isLandscape,
    );
  }

  void _drawCorner({
    required Canvas canvas,
    required Size size,
    required bool isLeft,
    required double leanDeg,
    required double oppositeLeanDeg,
    required bool isLandscape,
  }) {
    final w = size.width;
    final h = size.height;

    // Lean ratio normalized: 0.0 at upright (0 deg), 1.0 at 45+ deg
    final leanRatio = (leanDeg / 45.0).clamp(0.0, 1.0);
    final isOppositeActive = oppositeLeanDeg > 4.0;

    // Corner radius: base size covers corner badges, expands deeply on lean
    final minDim = min(w, h);
    final baseRadius = isLandscape ? minDim * 0.55 : minDim * 0.58;
    final expandedRadius = baseRadius * (1.0 + 0.55 * leanRatio) + (16.0 * breath * (0.6 + 0.4 * leanRatio));

    // Dynamic Alpha:
    // Upright / Idle: Visible, soothing ambient glow (~0.28 + breath)
    // Leaning: Vivid flare up to ~0.78 for instant peripheral recognition
    double baseAlpha = 0.28 + 0.42 * leanRatio + 0.08 * breath;
    if (isOppositeActive && leanDeg < 2.0) {
      baseAlpha *= 0.40; // Soften idle side while motorcycle is leaning the other way
    }
    baseAlpha = baseAlpha.clamp(0.10, 0.80);

    // Colors matching proposal sketch:
    // Corner: Apple Mint Green
    // Mid: Electric Yellow
    // Outer arc: Amber Orange
    // Crest: Racing Red
    const green = Color(0xFF30D158);
    const yellow = Color(0xFFFFD60A);
    const orange = Color(0xFFFF9500);
    const red = Color(0xFFFF3B30);
    final transparentWhite = Colors.white.withValues(alpha: 0.0);

    // Progressive color intensity based on lean:
    final redWeight = (leanRatio * 1.3).clamp(0.0, 1.0);
    final orangeWeight = ((leanRatio - 0.10) / 0.60).clamp(0.0, 1.0);

    final colors = <Color>[
      green.withValues(alpha: (baseAlpha * 0.95).clamp(0.0, 1.0)),
      Color.lerp(green, yellow, 0.6)!.withValues(alpha: (baseAlpha * 0.90).clamp(0.0, 1.0)),
      yellow.withValues(alpha: (baseAlpha * 0.85).clamp(0.0, 1.0)),
      Color.lerp(orange, red, redWeight)!.withValues(alpha: (baseAlpha * (0.45 + 0.55 * orangeWeight)).clamp(0.0, 1.0)),
      red.withValues(alpha: (baseAlpha * redWeight).clamp(0.0, 1.0)),
      transparentWhite,
    ];

    final stops = <double>[
      0.0,
      0.22,
      0.48,
      0.72,
      0.88,
      1.0,
    ];

    canvas.save();

    final originX = isLeft ? 0.0 : w;
    canvas.translate(originX, 0.0);

    // Elliptical shape matching the rider's contour sketch:
    // In portrait: stretch downward along screen edge (1.35x)
    // In landscape: stretch horizontally across top edge (1.30x)
    if (isLandscape) {
      canvas.scale(isLeft ? 1.30 : -1.30, 1.0);
    } else {
      canvas.scale(isLeft ? 1.0 : -1.0, 1.35);
    }

    final shader = ui.Gradient.radial(
      Offset.zero,
      expandedRadius,
      colors,
      stops,
      TileMode.clamp,
    );

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;

    // Draw smooth quadrant extending from the corner
    final rect = Rect.fromLTWH(0, 0, expandedRadius, expandedRadius);
    canvas.drawRect(rect, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CornerGradientPainter oldDelegate) {
    return oldDelegate.leftLean != leftLean ||
        oldDelegate.rightLean != rightLean ||
        oldDelegate.breath != breath;
  }
}
