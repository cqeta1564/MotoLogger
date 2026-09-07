import 'dart:math';
import 'package:flutter/material.dart';

/// Animated corner gradient wash that breathes and transitions color
/// based on real-time motorcycle lean angle from IMU / BNO085.
/// 
/// Strictly renders pure color blends (barevný přeliv) with zero harsh strokes.
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
      duration: const Duration(milliseconds: 2400),
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
        final breath = (sin(_controller.value * 2 * pi) + 1.0) / 2.0; // 0.0 to 1.0

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

  Color _getColorForLean(double deg) {
    if (deg < 12.0) {
      // 0 - 12 deg: Calm gentle green
      return const Color(0xFF34C759);
    } else if (deg < 25.0) {
      // 12 - 25 deg: Green to Yellow
      final t = (deg - 12.0) / 13.0;
      return Color.lerp(const Color(0xFF34C759), const Color(0xFFFFCC00), t)!;
    } else if (deg < 38.0) {
      // 25 - 38 deg: Yellow to Orange
      final t = (deg - 25.0) / 13.0;
      return Color.lerp(const Color(0xFFFFCC00), const Color(0xFFFF9500), t)!;
    } else {
      // 38+ deg: Orange to Racing Red
      final t = ((deg - 38.0) / 12.0).clamp(0.0, 1.0);
      return Color.lerp(const Color(0xFFFF9500), const Color(0xFFFF3B30), t)!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Radius of corner gradient wash scales with screen size
    final maxRadius = min(w, h) * 0.70;

    // Left Corner Gradient (Reacts to Left Lean)
    final leftColor = _getColorForLean(leftLean);
    final leftAlphaFactor = leftLean > 5.0 ? (0.35 + 0.30 * breath) : (0.20 + 0.15 * breath);
    final leftRadius = maxRadius * (leftLean > 5.0 ? (0.85 + 0.15 * breath) : (0.75 + 0.10 * breath));

    final leftPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-1.1, -1.1),
        radius: 1.0,
        colors: [
          leftColor.withOpacity((leftAlphaFactor * 1.1).clamp(0.0, 0.75)),
          leftColor.withOpacity((leftAlphaFactor * 0.6).clamp(0.0, 0.45)),
          leftColor.withOpacity((leftAlphaFactor * 0.2).clamp(0.0, 0.20)),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: leftRadius));

    canvas.drawCircle(Offset.zero, leftRadius, leftPaint);

    // Right Corner Gradient (Reacts to Right Lean)
    final rightColor = _getColorForLean(rightLean);
    final rightAlphaFactor = rightLean > 5.0 ? (0.35 + 0.30 * breath) : (0.20 + 0.15 * breath);
    final rightRadius = maxRadius * (rightLean > 5.0 ? (0.85 + 0.15 * breath) : (0.75 + 0.10 * breath));

    final rightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(1.1, -1.1),
        radius: 1.0,
        colors: [
          rightColor.withOpacity((rightAlphaFactor * 1.1).clamp(0.0, 0.75)),
          rightColor.withOpacity((rightAlphaFactor * 0.6).clamp(0.0, 0.45)),
          rightColor.withOpacity((rightAlphaFactor * 0.2).clamp(0.0, 0.20)),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(w, 0), radius: rightRadius));

    canvas.drawCircle(Offset(w, 0), rightRadius, rightPaint);
  }

  @override
  bool shouldRepaint(covariant _CornerGradientPainter oldDelegate) {
    return oldDelegate.leftLean != leftLean ||
        oldDelegate.rightLean != rightLean ||
        oldDelegate.breath != breath;
  }
}
