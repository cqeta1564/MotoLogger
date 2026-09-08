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

    // Normalized progress from 1.0 deg to 45.0 deg
    final t = ((leanDeg - 1.0) / 44.0).clamp(0.0, 1.0);

    // Spatial expansion factor: starts tiny at 1.0 deg and smoothly grows outward
    final sizeFactor = pow(t, 0.88).toDouble();

    // Max reach along top edge and side edge at full lean (45 deg+)
    final double maxTop = isLandscape ? (w * 0.38) : (w * 0.50);
    final double maxBottom = isLandscape ? (h * 0.80) : (h * 0.48);

    // Dynamic reach scaling directly from corner
    final topReach = (maxTop * sizeFactor + 4.0 * breath * sizeFactor).clamp(0.0, maxTop + 6.0);
    final bottomReach = (maxBottom * sizeFactor + 6.0 * breath * sizeFactor).clamp(0.0, maxBottom + 8.0);

    if (topReach < 1.0 || bottomReach < 1.0) return;

    // Alpha intensity: smoothly ramps up without sudden pop
    final alphaActivation = Curves.easeOut.transform(((leanDeg - 1.0) / 5.0).clamp(0.0, 1.0));
    final baseAlpha = (alphaActivation * (0.28 + 0.52 * t + 0.08 * breath)).clamp(0.0, 0.88);

    // Build the logarithmic curve path connecting top edge to side edge
    final path = Path();
    final curvePath = Path();

    if (isLeft) {
      final p0 = Offset(topReach, 0);
      final p1 = Offset(topReach * 0.65, bottomReach * 0.18);
      final p2 = Offset(topReach * 0.12, bottomReach * 0.62);
      final p3 = Offset(0, bottomReach);

      curvePath.moveTo(p0.dx, p0.dy);
      curvePath.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

      path.moveTo(0, 0);
      path.lineTo(p0.dx, p0.dy);
      path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
      path.lineTo(0, p3.dy);
      path.close();
    } else {
      // Right side
      final p0 = Offset(w - topReach, 0);
      final p1 = Offset(w - (topReach * 0.65), bottomReach * 0.18);
      final p2 = Offset(w - (topReach * 0.12), bottomReach * 0.62);
      final p3 = Offset(w, bottomReach);

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

    final double yellowMix = (t / 0.30).clamp(0.0, 1.0);
    final double orangeMix = ((t - 0.20) / 0.40).clamp(0.0, 1.0);
    final double redMix = ((t - 0.55) / 0.45).clamp(0.0, 1.0);

    final cCorner = green.withValues(alpha: (baseAlpha * 0.92).clamp(0.0, 1.0));
    final cMid = Color.lerp(green, yellow, yellowMix)!.withValues(alpha: (baseAlpha * 0.85).clamp(0.0, 1.0));
    final cWarm = Color.lerp(yellow, orange, orangeMix)!.withValues(alpha: (baseAlpha * (0.50 + 0.40 * orangeMix)).clamp(0.0, 1.0));
    final cEdge = Color.lerp(orange, red, redMix)!.withValues(alpha: (baseAlpha * (0.30 + 0.65 * redMix)).clamp(0.0, 1.0));
    final cFade = Colors.white.withValues(alpha: 0.0);

    // 1. Fill the corner canopy with smooth feathered dissipation
    final startOffset = isLeft ? Offset.zero : Offset(w, 0);
    final endOffset = isLeft
        ? Offset(topReach * 0.88, bottomReach * 0.88)
        : Offset(w - (topReach * 0.88), bottomReach * 0.88);

    final fillShader = ui.Gradient.linear(
      startOffset,
      endOffset,
      [cCorner, cMid, cWarm, cEdge, cFade],
      const [0.0, 0.28, 0.58, 0.85, 1.0],
    );

    // Soft blur feathering on the fill removes hard vector edges
    final fillPaint = Paint()
      ..shader = fillShader
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (3.0 + 8.0 * sizeFactor).clamp(2.0, 12.0));

    canvas.drawPath(path, fillPaint);

    // 2. Soft Glowing Wave along the leading edge (only as lean deepens)
    if (orangeMix > 0.05) {
      final outerGlowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (10.0 + 24.0 * t) * sizeFactor
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(orange, red, redMix)!
            .withValues(alpha: (baseAlpha * 0.35 * orangeMix).clamp(0.0, 0.65))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 * sizeFactor + 4.0);

      canvas.drawPath(curvePath, outerGlowPaint);
    }

    if (redMix > 0.05) {
      final innerCrestPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (4.0 + 10.0 * redMix) * sizeFactor
        ..strokeCap = StrokeCap.round
        ..color = red.withValues(alpha: (baseAlpha * 0.55 * redMix).clamp(0.0, 0.85))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 * sizeFactor + 2.0);

      canvas.drawPath(curvePath, innerCrestPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerGradientPainter oldDelegate) {
    return oldDelegate.leftLean != leftLean ||
        oldDelegate.rightLean != rightLean ||
        oldDelegate.breath != breath;
  }
}
