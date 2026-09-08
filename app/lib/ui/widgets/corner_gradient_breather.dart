import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Animated corner gradient wash that breathes and transitions color
/// based on real-time motorcycle lean angle from IMU / BNO085.
/// 
/// Renders a logarithmic canopy edge originating from the top-center edge
/// and sweeping down the sides (Green -> Yellow -> Orange -> Racing Red),
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

    // 1. LEFT CORNER: Logarithmic canopy from top center down to left edge
    _drawLogarithmicCorner(
      canvas: canvas,
      size: size,
      isLeft: true,
      leanDeg: leftLean,
      oppositeLeanDeg: rightLean,
      isLandscape: isLandscape,
    );

    // 2. RIGHT CORNER: Logarithmic canopy from top center down to right edge
    _drawLogarithmicCorner(
      canvas: canvas,
      size: size,
      isLeft: false,
      leanDeg: rightLean,
      oppositeLeanDeg: leftLean,
      isLandscape: isLandscape,
    );
  }

  void _drawLogarithmicCorner({
    required Canvas canvas,
    required Size size,
    required bool isLeft,
    required double leanDeg,
    required double oppositeLeanDeg,
    required bool isLandscape,
  }) {
    final w = size.width;
    final h = size.height;

    // 100% clean: if motorcycle is upright (<= 1.0 deg), render zero color
    if (leanDeg <= 1.0) return;

    // Smooth entry curve from 1.0 to 5.0 degrees
    final activation = Curves.easeOut.transform(((leanDeg - 1.0) / 4.0).clamp(0.0, 1.0));
    final leanRatio = ((leanDeg - 1.0) / 44.0).clamp(0.0, 1.0);

    // Dynamic anchor points:
    // P0: Top edge (starts near center of top edge)
    // P3: Side edge (reaches down the left/right edge)
    final double xTop;
    final double yBottom;

    if (isLandscape) {
      final baseTop = w * 0.36;
      final baseBottom = h * 0.76;
      xTop = baseTop + (w * 0.08 * leanRatio) + (6.0 * breath);
      yBottom = (baseBottom + (h * 0.16 * leanRatio) + (8.0 * breath)).clamp(0.0, h);
    } else {
      // In portrait: starts at the center of the top edge (w * 0.50)
      final baseTop = w * 0.50;
      final baseBottom = h * 0.44;
      xTop = (baseTop + (w * 0.04 * (isLeft ? leanRatio : -leanRatio)) + (4.0 * breath * (isLeft ? 1 : -1))).clamp(w * 0.36, w * 0.64);
      yBottom = (baseBottom + (h * 0.14 * leanRatio) + (10.0 * breath)).clamp(0.0, h * 0.72);
    }

    // Alpha intensity: completely 0.0 at <= 1.0 deg, ramping up to ~0.88 at deep lean
    final baseAlpha = (activation * (0.35 + 0.45 * leanRatio + 0.08 * breath)).clamp(0.0, 0.88);

    // Build the logarithmic curve path
    final path = Path();
    final curvePath = Path();

    if (isLeft) {
      final p0 = Offset(xTop, 0);
      final p1 = Offset(xTop * 0.70, yBottom * 0.18);
      final p2 = Offset(w * 0.06, yBottom * 0.56);
      final p3 = Offset(0, yBottom);

      curvePath.moveTo(p0.dx, p0.dy);
      curvePath.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

      path.moveTo(0, 0);
      path.lineTo(p0.dx, p0.dy);
      path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
      path.lineTo(0, p3.dy);
      path.close();
    } else {
      // Right side
      final startX = isLandscape ? (w - xTop) : xTop;
      final p0 = Offset(startX, 0);
      final p1 = Offset(w - (xTop * 0.70), yBottom * 0.18);
      final p2 = Offset(w - (w * 0.06), yBottom * 0.56);
      final p3 = Offset(w, yBottom);

      curvePath.moveTo(p0.dx, p0.dy);
      curvePath.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

      path.moveTo(w, 0);
      path.lineTo(p0.dx, p0.dy);
      path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
      path.lineTo(w, p3.dy);
      path.close();
    }

    // Palette matching proposal:
    // Corner: Apple Mint Green
    // Mid: Vibrant Electric Yellow
    // Wave: Amber Orange
    // Leading Logarithmic Edge: Racing Red
    const green = Color(0xFF30D158);
    const yellow = Color(0xFFFFD60A);
    const orange = Color(0xFFFF9500);
    const red = Color(0xFFFF3B30);

    final redWeight = (leanRatio * 1.3).clamp(0.0, 1.0);
    final orangeWeight = ((leanRatio - 0.10) / 0.60).clamp(0.0, 1.0);

    // 1. Fill the corner canopy with smooth color blend
    final startOffset = isLeft ? Offset.zero : Offset(w, 0);
    final endOffset = isLeft ? Offset(xTop * 0.85, yBottom * 0.85) : Offset(w - (xTop * 0.85), yBottom * 0.85);

    final fillShader = ui.Gradient.linear(
      startOffset,
      endOffset,
      [
        green.withValues(alpha: (baseAlpha * 0.90).clamp(0.0, 1.0)),
        Color.lerp(green, yellow, 0.6)!.withValues(alpha: (baseAlpha * 0.85).clamp(0.0, 1.0)),
        yellow.withValues(alpha: (baseAlpha * 0.80).clamp(0.0, 1.0)),
        Color.lerp(orange, red, redWeight)!.withValues(alpha: (baseAlpha * (0.50 + 0.50 * orangeWeight)).clamp(0.0, 1.0)),
        red.withValues(alpha: (baseAlpha * (0.35 + 0.65 * redWeight)).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: 0.0),
      ],
      const [0.0, 0.25, 0.52, 0.75, 0.92, 1.0],
    );

    final fillPaint = Paint()
      ..shader = fillShader
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // 2. Soft Glowing Wave along the logarithmic edge (Barevný přeliv na hraně)
    // Outer wide glow (Amber Orange / Red)
    final outerGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 36.0 + 14.0 * leanRatio
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(orange, red, redWeight)!.withValues(alpha: (baseAlpha * (0.28 + 0.45 * orangeWeight)).clamp(0.0, 0.72))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0);

    canvas.drawPath(curvePath, outerGlowPaint);

    // Inner bright crest glow (Racing Red)
    final innerCrestPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0 + 8.0 * leanRatio
      ..strokeCap = StrokeCap.round
      ..color = red.withValues(alpha: (baseAlpha * (0.40 + 0.55 * redWeight)).clamp(0.0, 0.88))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

    canvas.drawPath(curvePath, innerCrestPaint);
  }

  @override
  bool shouldRepaint(covariant _CornerGradientPainter oldDelegate) {
    return oldDelegate.leftLean != leftLean ||
        oldDelegate.rightLean != rightLean ||
        oldDelegate.breath != breath;
  }
}
