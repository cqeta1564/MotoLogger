import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/motion/app_motion.dart';
import '../../core/preferences/app_preferences.dart';

/// Directional lean feedback. Negative angles are left; positive are right.
/// Retains the original 1° dead zone and 45° full-scale visual range.
/// Colors describe angle magnitude, not a traction or safety measurement.
class CornerGradientBreather extends StatelessWidget {
  const CornerGradientBreather({
    super.key,
    required this.leanAngleDeg,
    this.enabled = true,
  });

  final double leanAngleDeg;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final angle = enabled && leanAngleDeg.isFinite
        ? leanAngleDeg.clamp(-90.0, 90.0)
        : 0.0;
    final media = MediaQuery.of(context);
    final opaque = media.highContrast ||
        media.accessibleNavigation ||
        (AppPreferencesScope.maybeOf(context)?.reduceTransparency ?? false);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            // Reset immediately when a connection is lost, without stale glow.
            key: ValueKey(enabled),
            tween: Tween(begin: angle, end: angle),
            duration: AppMotion.duration(context, 100),
            curve: Curves.linear,
            builder: (context, value, _) => CustomPaint(
              size: Size.infinite,
              painter: LeanEdgePainter(angle: value, opaque: opaque),
            ),
          ),
        ),
      ),
    );
  }
}

class LeanEdgePainter extends CustomPainter {
  const LeanEdgePainter({required this.angle, required this.opaque});
  final double angle;
  final bool opaque;

  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);
  static const red = Color(0xFFFF3B30);

  static Color colorFor(double magnitude) {
    final degrees = magnitude.abs();
    if (degrees <= 15) return green;
    if (degrees <= 30) return Color.lerp(green, orange, (degrees - 15) / 15)!;
    return Color.lerp(orange, red, ((degrees - 30) / 15).clamp(0, 1))!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!angle.isFinite || angle.abs() <= 1 || size.isEmpty) return;
    final progress = ((angle.abs() - 1) / 44).clamp(0.0, 1.0);
    final activation = ((angle.abs() - 1) / 5).clamp(0.0, 1.0);
    final color = colorFor(angle);
    final left = angle < 0;
    final width = opaque ? 4.0 : math.min(size.width * .19, 80.0);
    final rect =
        Rect.fromLTWH(left ? 0 : size.width - width, 0, width, size.height);
    final paint = Paint();
    if (opaque) {
      paint.color = color;
    } else {
      paint.shader = LinearGradient(
        begin: left ? Alignment.centerLeft : Alignment.centerRight,
        end: left ? Alignment.centerRight : Alignment.centerLeft,
        colors: [
          color.withValues(alpha: activation * (.22 + .43 * progress)),
          color.withValues(alpha: activation * (.08 + .12 * progress)),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .3, 1],
      ).createShader(rect);
    }
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(LeanEdgePainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.opaque != opaque;
}
