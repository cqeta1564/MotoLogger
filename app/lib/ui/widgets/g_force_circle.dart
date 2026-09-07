import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GForceCircle extends StatelessWidget {
  final double accelX; // Longitudinal G (+ accel, - braking)
  final double accelY; // Lateral G (+ right, - left)
  final double size;

  const GForceCircle({
    super.key,
    required this.accelX,
    required this.accelY,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GForcePainter(accelX: accelX, accelY: accelY),
      ),
    );
  }
}

class _GForcePainter extends CustomPainter {
  final double accelX;
  final double accelY;

  _GForcePainter({required this.accelX, required this.accelY});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.45; // Corresponds to 1.5G

    // Grid circles: 0.5G, 1.0G, 1.5G
    final gridPaint = Paint()
      ..color = AppTheme.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, maxRadius * (0.5 / 1.5), gridPaint);
    canvas.drawCircle(center, maxRadius * (1.0 / 1.5), gridPaint);
    canvas.drawCircle(center, maxRadius, gridPaint);

    // Crosshairs
    final axisPaint = Paint()
      ..color = AppTheme.textMuted.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);

    // Calculate dynamic ball position
    // Note: accelY = lateral (left/right), accelX = longitudinal (accel/braking)
    final clampedX = accelY.clamp(-1.5, 1.5);
    final clampedY = -accelX.clamp(-1.5, 1.5); // Invert so braking is top, accel is bottom

    final ballX = center.dx + (clampedX / 1.5) * maxRadius;
    final ballY = center.dy + (clampedY / 1.5) * maxRadius;
    final ballCenter = Offset(ballX, ballY);

    // Total G
    final totalG = sqrt(accelX * accelX + accelY * accelY);

    Color ballColor = AppTheme.primary;
    if (totalG > 1.1) {
      ballColor = AppTheme.danger;
    } else if (totalG > 0.8) {
      ballColor = AppTheme.accent;
    }

    // Glow aura
    canvas.drawCircle(
      ballCenter,
      10,
      Paint()
        ..color = ballColor.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Ball
    canvas.drawCircle(ballCenter, 5.5, Paint()..color = ballColor);

    // Center cross marker
    canvas.drawCircle(center, 2, Paint()..color = AppTheme.textMuted);
  }

  @override
  bool shouldRepaint(covariant _GForcePainter oldDelegate) {
    return oldDelegate.accelX != accelX || oldDelegate.accelY != accelY;
  }
}
