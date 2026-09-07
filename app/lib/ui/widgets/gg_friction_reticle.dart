import 'dart:math';
import 'package:flutter/material.dart';

/// Professional G-G Traction Reticle (Friction Circle) that renders directly
/// on the canvas without any bounding card/box.
/// 
/// Displays:
/// 1. Dark crosshairs and origin.
/// 2. Concentric reference circles (0.5G dashed, 1.0G solid).
/// 3. Dynamic red polar friction envelope polygon tracing recorded grip limits.
/// 4. Live instantaneous acceleration/braking/cornering G-dot.
class GgFrictionReticle extends StatelessWidget {
  final double accelXG; // Lateral acceleration (+ = Right, - = Left)
  final double accelYG; // Longitudinal acceleration (+ = Accel, - = Braking)
  final List<double> frictionEnvelope; // Polar max radii for 36 sectors
  final double size;
  final double maxGRange; // Default 1.2G outer scale

  const GgFrictionReticle({
    super.key,
    required this.accelXG,
    required this.accelYG,
    required this.frictionEnvelope,
    this.size = 260.0,
    this.maxGRange = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GgFrictionPainter(
        accelXG: accelXG,
        accelYG: accelYG,
        frictionEnvelope: frictionEnvelope,
        maxGRange: maxGRange,
      ),
    );
  }
}

class _GgFrictionPainter extends CustomPainter {
  final double accelXG;
  final double accelYG;
  final List<double> frictionEnvelope;
  final double maxGRange;

  _GgFrictionPainter({
    required this.accelXG,
    required this.accelYG,
    required this.frictionEnvelope,
    required this.maxGRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius1G = (size.width / 2) * (1.0 / maxGRange);
    final radius05G = radius1G * 0.5;

    // 1. Crosshairs
    final axisPaint = Paint()
      ..color = const Color(0xFF1C1C1E)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Horizontal axis (Lateral G)
    canvas.drawLine(
      Offset(center.dx - radius1G * 1.25, center.dy),
      Offset(center.dx + radius1G * 1.25, center.dy),
      axisPaint,
    );
    // Vertical axis (Longitudinal G: braking down, accel up)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius1G * 1.25),
      Offset(center.dx, center.dy + radius1G * 1.25),
      axisPaint,
    );

    // 2. Concentric Reference Circles
    // Outer 1.0G Circle (Solid)
    final ring1GPaint = Paint()
      ..color = const Color(0xFF1C1C1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius1G, ring1GPaint);

    // Inner 0.5G Circle (Dashed)
    final dashPaint = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashCount = 36;
    const dashAngle = (2 * pi) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius05G),
        i * dashAngle,
        dashAngle * 0.65,
        false,
        dashPaint,
      );
    }

    // Origin center dot
    canvas.drawCircle(center, 4.0, Paint()..color = const Color(0xFF1C1C1E));

    // Reference Typography (1.0G and 0.5G)
    const textStyle1G = TextStyle(
      color: Color(0xFF8E8E93),
      fontSize: 10,
      fontWeight: FontWeight.w800,
      fontFamily: '-apple-system',
    );
    final tp1G = TextPainter(
      text: const TextSpan(text: '1.0G', style: textStyle1G),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1G.paint(canvas, Offset(center.dx + 6, center.dy - radius1G + 3));

    const textStyle05G = TextStyle(
      color: Color(0xFFAEAEB2),
      fontSize: 9,
      fontWeight: FontWeight.w700,
      fontFamily: '-apple-system',
    );
    final tp05G = TextPainter(
      text: const TextSpan(text: '0.5G', style: textStyle05G),
      textDirection: TextDirection.ltr,
    )..layout();
    tp05G.paint(canvas, Offset(center.dx + 6, center.dy - radius05G + 3));

    // 3. Red Friction Envelope Polygon (Recorded Traction Limits)
    if (frictionEnvelope.isNotEmpty) {
      final envelopePath = Path();
      final sectorCount = frictionEnvelope.length;
      final stepAngle = (2 * pi) / sectorCount;

      List<Offset> points = [];
      for (int i = 0; i < sectorCount; i++) {
        final angle = i * stepAngle;
        // Clamp radius for visualization
        final gVal = frictionEnvelope[i].clamp(0.12, maxGRange);
        final rPx = (gVal / maxGRange) * (size.width / 2);
        // Note: accelX is horizontal (cos), accelY is vertical (sin: + is accel/up, so -y)
        final px = center.dx + rPx * cos(angle);
        final py = center.dy - rPx * sin(angle);
        points.add(Offset(px, py));
      }

      if (points.isNotEmpty) {
        envelopePath.moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          envelopePath.lineTo(points[i].dx, points[i].dy);
        }
        envelopePath.close();

        // Fill semi-transparent red
        final fillPaint = Paint()
          ..color = const Color(0x26FF3B30)
          ..style = PaintingStyle.fill;
        canvas.drawPath(envelopePath, fillPaint);

        // Stroke crisp red outline
        final strokePaint = Paint()
          ..color = const Color(0xFFFF3B30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(envelopePath, strokePaint);
      }
    }

    // 4. Instantaneous G-Force Active Dot
    // Lateral G -> X, Longitudinal G -> Y (accel up = -y, brake down = +y)
    final clampedX = accelXG.clamp(-maxGRange, maxGRange);
    final clampedY = accelYG.clamp(-maxGRange, maxGRange);

    final dotX = center.dx + (clampedX / maxGRange) * (size.width / 2);
    final dotY = center.dy - (clampedY / maxGRange) * (size.width / 2);
    final dotOffset = Offset(dotX, dotY);

    // Drop shadow
    canvas.drawCircle(
      dotOffset.translate(0, 3),
      11.0,
      Paint()
        ..color = const Color(0x55FF3B30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    // White border ring
    canvas.drawCircle(
      dotOffset,
      10.0,
      Paint()..color = Colors.white,
    );

    // Red core dot
    canvas.drawCircle(
      dotOffset,
      7.5,
      Paint()..color = const Color(0xFFFF3B30),
    );
  }

  @override
  bool shouldRepaint(covariant _GgFrictionPainter oldDelegate) {
    return oldDelegate.accelXG != accelXG ||
        oldDelegate.accelYG != accelYG ||
        oldDelegate.frictionEnvelope != frictionEnvelope ||
        oldDelegate.maxGRange != maxGRange;
  }
}
