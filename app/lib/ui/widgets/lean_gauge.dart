import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LeanGauge extends StatelessWidget {
  final double leanAngleDeg;    // Current lean angle (-60.0 to +60.0)
  final double maxLeftDeg;      // Maximum left lean recorded
  final double maxRightDeg;     // Maximum right lean recorded
  final double size;

  const LeanGauge({
    super.key,
    required this.leanAngleDeg,
    required this.maxLeftDeg,
    required this.maxRightDeg,
    this.size = 280,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.75,
      child: CustomPaint(
        painter: _LeanGaugePainter(
          leanAngle: leanAngleDeg,
          maxLeft: maxLeftDeg,
          maxRight: maxRightDeg,
        ),
      ),
    );
  }
}

class _LeanGaugePainter extends CustomPainter {
  final double leanAngle;
  final double maxLeft;
  final double maxRight;

  _LeanGaugePainter({
    required this.leanAngle,
    required this.maxLeft,
    required this.maxRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.85);
    final radius = size.width * 0.42;

    final basePaint = Paint()
      ..color = AppTheme.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    // Draw background arc from -60 deg to +60 deg
    // 0 deg (vertical) is at top: -pi/2
    const minAngleRad = -pi / 3; // -60 degrees
    const maxAngleRad = pi / 3;  // +60 degrees
    const startAngle = -pi / 2 + minAngleRad;
    const sweepAngle = maxAngleRad - minAngleRad; // 120 degrees sweep

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      basePaint,
    );

    // Draw active lean arc
    final currentRad = (leanAngle * pi / 180.0).clamp(minAngleRad, maxAngleRad);
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    if (leanAngle.abs() > 48.0) {
      activePaint.color = AppTheme.danger;
    } else if (leanAngle.abs() > 38.0) {
      activePaint.color = AppTheme.accent;
    } else {
      activePaint.color = AppTheme.primary;
    }

    if (currentRad != 0) {
      final activeStart = -pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        activeStart,
        currentRad,
        false,
        activePaint,
      );
    }

    // Draw Peak Left & Right tick markers
    final peakPaint = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    if (maxLeft < 0) {
      final leftAngle = -pi / 2 + (maxLeft * pi / 180.0).clamp(minAngleRad, 0.0);
      final p1 = Offset(center.dx + (radius - 12) * cos(leftAngle), center.dy + (radius - 12) * sin(leftAngle));
      final p2 = Offset(center.dx + (radius + 12) * cos(leftAngle), center.dy + (radius + 12) * sin(leftAngle));
      canvas.drawLine(p1, p2, peakPaint);
    }

    if (maxRight > 0) {
      final rightAngle = -pi / 2 + (maxRight * pi / 180.0).clamp(0.0, maxAngleRad);
      final p1 = Offset(center.dx + (radius - 12) * cos(rightAngle), center.dy + (radius - 12) * sin(rightAngle));
      final p2 = Offset(center.dx + (radius + 12) * cos(rightAngle), center.dy + (radius + 12) * sin(rightAngle));
      canvas.drawLine(p1, p2, peakPaint);
    }

    // Draw Dynamic Horizon Needle / Motorcycle Indicator
    final needleAngle = -pi / 2 + currentRad;
    final needlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final needleEnd = Offset(
      center.dx + (radius + 6) * cos(needleAngle),
      center.dy + (radius + 6) * sin(needleAngle),
    );
    final needleStart = Offset(
      center.dx + (radius - 24) * cos(needleAngle),
      center.dy + (radius - 24) * sin(needleAngle),
    );
    canvas.drawLine(needleStart, needleEnd, needlePaint);

    // Center pivot indicator
    canvas.drawCircle(center, 4, Paint()..color = AppTheme.textMuted);

    // Digital text readout in the center
    final angleStr = '${leanAngle.abs().toStringAsFixed(1)}°';
    final sideStr = leanAngle > 0.5 ? 'RIGHT' : (leanAngle < -0.5 ? 'LEFT' : 'UPRIGHT');

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$angleStr\n',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: sideStr,
            style: TextStyle(
              color: activePaint.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - radius * 0.7));
  }

  @override
  bool shouldRepaint(covariant _LeanGaugePainter oldDelegate) {
    return oldDelegate.leanAngle != leanAngle ||
        oldDelegate.maxLeft != maxLeft ||
        oldDelegate.maxRight != maxRight;
  }
}
