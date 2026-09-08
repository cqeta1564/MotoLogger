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

    // Palette matching Apple iOS Design System:
    // Corner: Apple Mint Green with subtle Teal hint
    // Mid: Vibrant Electric Gold/Yellow
    // Wave: Apple Tangerine / Amber
    // Leading Logarithmic Edge: Apple Racing Red
    const green = Color(0xFF30D158);
    const teal = Color(0xFF30B0C7);
    const yellow = Color(0xFFFFD60A);
    const orange = Color(0xFFFF9500);
    const red = Color(0xFFFF3B30);

    final double yellowMix = (t / 0.30).clamp(0.0, 1.0);
    final double orangeMix = ((t - 0.20) / 0.40).clamp(0.0, 1.0);
    final double redMix = ((t - 0.55) / 0.45).clamp(0.0, 1.0);

    // Dynamic Apple color nodes
    final cRoot = Color.lerp(green, teal, 0.25)!.withValues(alpha: (baseAlpha * 0.95).clamp(0.0, 1.0));
    final cMid = Color.lerp(green, yellow, yellowMix)!.withValues(alpha: (baseAlpha * 0.88).clamp(0.0, 1.0));
    final cWarm = Color.lerp(yellow, orange, orangeMix)!.withValues(alpha: (baseAlpha * (0.55 + 0.35 * orangeMix)).clamp(0.0, 1.0));
    final cEdge = Color.lerp(orange, red, redMix)!.withValues(alpha: (baseAlpha * (0.35 + 0.60 * redMix)).clamp(0.0, 1.0));
    final cFade = Colors.white.withValues(alpha: 0.0);

    // --- LAYER 1: Ambient Luminous Bloom (Apple Gaussian Aurora) ---
    final cornerOrigin = isLeft ? Offset.zero : Offset(w, 0);
    final ambientRadius = (topReach + bottomReach) * 0.82;
    final ambientShader = ui.Gradient.radial(
      cornerOrigin,
      ambientRadius,
      [
        cRoot.withValues(alpha: (baseAlpha * 0.40).clamp(0.0, 1.0)),
        cMid.withValues(alpha: (baseAlpha * 0.30).clamp(0.0, 1.0)),
        cWarm.withValues(alpha: (baseAlpha * 0.18 * orangeMix).clamp(0.0, 1.0)),
        cFade,
      ],
      const [0.0, 0.42, 0.75, 1.0],
    );

    final ambientPaint = Paint()
      ..shader = ambientShader
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (18.0 * sizeFactor + 6.0).clamp(4.0, 32.0));

    canvas.drawPath(path, ambientPaint);

    // --- LAYER 2: Fluid Logarithmic Canopy Fill with Feathered Dissipation ---
    final startOffset = isLeft ? Offset.zero : Offset(w, 0);
    final endOffset = isLeft
        ? Offset(topReach * 0.88, bottomReach * 0.88)
        : Offset(w - (topReach * 0.88), bottomReach * 0.88);

    final fillShader = ui.Gradient.linear(
      startOffset,
      endOffset,
      [cRoot, cMid, cWarm, cEdge, cFade],
      const [0.0, 0.28, 0.58, 0.86, 1.0],
    );

    final fillPaint = Paint()
      ..shader = fillShader
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (4.0 + 8.0 * sizeFactor).clamp(2.5, 14.0));

    canvas.drawPath(path, fillPaint);

    // --- LAYER 3: Specular Neon Crest Filament (Apple Edge Lighting) ---
    if (orangeMix > 0.05) {
      // Pass A: Soft Ambient Edge Bloom
      final edgeHaloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (12.0 + 20.0 * t) * sizeFactor
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(orange, red, redMix)!
            .withValues(alpha: (baseAlpha * 0.35 * orangeMix).clamp(0.0, 0.65))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 * sizeFactor + 4.0);

      canvas.drawPath(curvePath, edgeHaloPaint);

      // Pass B: Precision Luminous Core Filament (Crystalline glass edge)
      final coreFilamentPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 + 3.8 * t) * sizeFactor
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(orange, red, redMix)!
            .withValues(alpha: (baseAlpha * 0.78 * orangeMix).clamp(0.0, 0.90))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * sizeFactor + 0.8);

      canvas.drawPath(curvePath, coreFilamentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerGradientPainter oldDelegate) {
    return oldDelegate.leftLean != leftLean ||
        oldDelegate.rightLean != rightLean ||
        oldDelegate.breath != breath;
  }
}
