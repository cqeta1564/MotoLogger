import 'dart:math';
import 'dart:ui' as ui;
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
    final outerRadius = size.width / 2;

    // 1. Subtle Hairline Crosshairs with Center Clearance (Apple Instrument Style)
    final axisPaint = Paint()
      ..color = const Color(0xFFE5E5EA)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    const centerGap = 12.0;

    // Horizontal axis (Lateral G)
    canvas.drawLine(
      Offset(center.dx - radius1G * 1.18, center.dy),
      Offset(center.dx - centerGap, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx + centerGap, center.dy),
      Offset(center.dx + radius1G * 1.18, center.dy),
      axisPaint,
    );

    // Vertical axis (Longitudinal G)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius1G * 1.18),
      Offset(center.dx, center.dy - centerGap),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + centerGap),
      Offset(center.dx, center.dy + radius1G * 1.18),
      axisPaint,
    );

    // 2. Concentric Reference Circles (Apple Precision Design)
    // Outer scale container boundary (1.2G limit)
    final boundaryPaint = Paint()
      ..color = const Color(0xFFF2F2F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, outerRadius, boundaryPaint);

    // Primary 1.0G Reference Ring (Crisp Hairline)
    final ring1GPaint = Paint()
      ..color = const Color(0xFFD1D1D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius1G, ring1GPaint);

    // Cardinal Tick Marks at 1.0G (12, 3, 6, 9 o'clock)
    final tickPaint = Paint()
      ..color = const Color(0xFFAEAEB2)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const tickLen = 4.0;
    canvas.drawLine(Offset(center.dx, center.dy - radius1G - tickLen), Offset(center.dx, center.dy - radius1G + tickLen), tickPaint);
    canvas.drawLine(Offset(center.dx, center.dy + radius1G - tickLen), Offset(center.dx, center.dy + radius1G + tickLen), tickPaint);
    canvas.drawLine(Offset(center.dx - radius1G - tickLen, center.dy), Offset(center.dx - radius1G + tickLen, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx + radius1G - tickLen, center.dy), Offset(center.dx + radius1G + tickLen, center.dy), tickPaint);

    // Inner 0.5G Reference Ring (Delicate Dashed)
    final dashPaint = Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const dashCount = 36;
    const dashAngle = (2 * pi) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius05G),
        i * dashAngle,
        dashAngle * 0.60,
        false,
        dashPaint,
      );
    }

    // Center Origin Reticle (Tiny jewel target)
    canvas.drawCircle(center, 5.0, Paint()..color = const Color(0xFFF2F2F7));
    canvas.drawCircle(center, 2.5, Paint()..color = const Color(0xFF8E8E93));

    // Reference Typography (Apple SF Pro Caption Style)
    const textStyle1G = TextStyle(
      color: Color(0xFF8E8E93),
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      fontFamily: '-apple-system',
    );
    final tp1G = TextPainter(
      text: const TextSpan(text: '1.0G', style: textStyle1G),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1G.paint(canvas, Offset(center.dx + 6, center.dy - radius1G + 3));

    const textStyle05G = TextStyle(
      color: Color(0xFFAEAEB2),
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      fontFamily: '-apple-system',
    );
    final tp05G = TextPainter(
      text: const TextSpan(text: '0.5G', style: textStyle05G),
      textDirection: TextDirection.ltr,
    )..layout();
    tp05G.paint(canvas, Offset(center.dx + 6, center.dy - radius05G + 3));

    // 3. Red Friction Envelope (Smooth Catmull-Rom Bezier Spline)
    if (frictionEnvelope.isNotEmpty) {
      final sectorCount = frictionEnvelope.length;
      final stepAngle = (2 * pi) / sectorCount;

      List<Offset> points = [];
      for (int i = 0; i < sectorCount; i++) {
        final angle = i * stepAngle;
        final gVal = frictionEnvelope[i].clamp(0.12, maxGRange);
        final rPx = (gVal / maxGRange) * (size.width / 2);
        final px = center.dx + rPx * cos(angle);
        final py = center.dy - rPx * sin(angle);
        points.add(Offset(px, py));
      }

      if (points.length >= 3) {
        final envelopePath = _createSmoothClosedSpline(points);

        // Apple Soft Radial Glow Fill
        final fillShader = ui.Gradient.radial(
          center,
          radius1G * 1.1,
          [
            const Color(0x28FF3B30),
            const Color(0x14FF9500),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.72, 1.0],
        );

        final fillPaint = Paint()
          ..shader = fillShader
          ..style = PaintingStyle.fill;
        canvas.drawPath(envelopePath, fillPaint);

        // Apple Crisp Glowing Boundary Stroke
        final strokePaint = Paint()
          ..color = const Color(0xFFFF3B30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(envelopePath, strokePaint);
      }
    }

    // 4. Instantaneous G-Force Active Puck (Apple Glass Jewel Design)
    final clampedX = accelXG.clamp(-maxGRange, maxGRange);
    final clampedY = accelYG.clamp(-maxGRange, maxGRange);

    final dotX = center.dx + (clampedX / maxGRange) * (size.width / 2);
    final dotY = center.dy - (clampedY / maxGRange) * (size.width / 2);
    final dotOffset = Offset(dotX, dotY);

    // Layer 1: Ambient Red Pulse Glow
    canvas.drawCircle(
      dotOffset,
      13.0,
      Paint()
        ..color = const Color(0x35FF3B30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0),
    );

    // Layer 2: Pristine White Border with Subtle Drop Shadow
    canvas.drawCircle(
      dotOffset.translate(0, 1.5),
      9.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawCircle(
      dotOffset,
      9.5,
      Paint()..color = Colors.white,
    );

    // Layer 3: Radiant Apple Red Core
    canvas.drawCircle(
      dotOffset,
      7.0,
      Paint()..color = const Color(0xFFFF3B30),
    );

    // Layer 4: Specular Glass Reflection Highlight (Apple 3D Gemstone feel)
    canvas.drawCircle(
      dotOffset.translate(-2.0, -2.0),
      1.8,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  /// Converts polar envelope points into a mathematically smooth, continuous closed spline
  Path _createSmoothClosedSpline(List<Offset> points) {
    final path = Path();
    final n = points.length;
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];

      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _GgFrictionPainter oldDelegate) {
    return oldDelegate.accelXG != accelXG ||
        oldDelegate.accelYG != accelYG ||
        oldDelegate.frictionEnvelope != frictionEnvelope ||
        oldDelegate.maxGRange != maxGRange;
  }
}
