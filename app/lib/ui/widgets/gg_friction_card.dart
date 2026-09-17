import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fused_sample.dart';

/// Post-ride G-G Friction Diagram card analyzing the motorcycle tire grip envelope.
/// Displays:
/// 1. Polar 36-sector friction ellipse outlining peak grip during braking & cornering.
/// 2. Density scatter points showing real operating dynamic envelope.
/// 3. Summary metrics for peak Braking G, Acceleration G, and Left/Right Cornering G.
class GgFrictionCard extends StatelessWidget {
  final List<FusedSample> samples;

  const GgFrictionCard({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    // 1. Calculate peak dynamics and 36-sector polar envelope
    final envelope = List.filled(36, 0.15);
    double maxBrakeG = 0.0;
    double maxAccelG = 0.0;
    double maxLeftG = 0.0;
    double maxRightG = 0.0;
    double maxTotalG = 0.0;

    for (final s in samples) {
      if (s.accelYG < maxBrakeG) maxBrakeG = s.accelYG;
      if (s.accelYG > maxAccelG) maxAccelG = s.accelYG;
      if (s.accelXG < maxLeftG) maxLeftG = s.accelXG;
      if (s.accelXG > maxRightG) maxRightG = s.accelXG;

      final currentG = sqrt(s.accelXG * s.accelXG + s.accelYG * s.accelYG);
      if (currentG > maxTotalG) maxTotalG = currentG;

      if (currentG > 0.05) {
        double angle = atan2(s.accelYG, s.accelXG);
        if (angle < 0) angle += 2 * pi;
        final sector = ((angle / (2 * pi)) * 36).floor() % 36;
        if (currentG > envelope[sector]) {
          envelope[sector] = currentG;
        }
      }
    }

    // Subsample up to 400 scatter points for high-performance fluid rendering
    final scatterPoints = <Offset>[];
    final step = (samples.length / 400).clamp(1, 1000).ceil();
    for (int i = 0; i < samples.length; i += step) {
      final s = samples[i];
      if (s.accelXG.abs() > 0.02 || s.accelYG.abs() > 0.02) {
        scatterPoints.add(Offset(s.accelXG, s.accelYG));
      }
    }

    final double maxGRange = max(1.2, (maxTotalG * 1.15).clamp(1.2, 2.0));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'FRIKČNÍ DIAGRAM G-G',
            style: TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Využití přilnavosti pneumatik (brzdy vs. zatáčení)',
            style: TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),

          // G-G Diagram Canvas
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: CustomPaint(
                size: const Size(240, 240),
                painter: _GgFrictionCardPainter(
                  envelope: envelope,
                  scatterPoints: scatterPoints,
                  maxGRange: maxGRange,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Peak G Metrics 2x2 Apple Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Max. brzdění',
                  value: '${maxBrakeG.abs().toStringAsFixed(2)} G',
                  icon: Icons.south_rounded,
                  color: AppTheme.appleRed,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Max. zrychlení',
                  value: '+${maxAccelG.toStringAsFixed(2)} G',
                  icon: Icons.north_rounded,
                  color: AppTheme.appleGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Levý náklon G',
                  value: '${maxLeftG.abs().toStringAsFixed(2)} G',
                  icon: Icons.west_rounded,
                  color: AppTheme.appleBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Pravý náklon G',
                  value: '${maxRightG.toStringAsFixed(2)} G',
                  icon: Icons.east_rounded,
                  color: AppTheme.appleOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.appleBlack,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GgFrictionCardPainter extends CustomPainter {
  final List<double> envelope;
  final List<Offset> scatterPoints;
  final double maxGRange;

  _GgFrictionCardPainter({
    required this.envelope,
    required this.scatterPoints,
    required this.maxGRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius1G = (size.width / 2) * (1.0 / maxGRange);
    final radius05G = radius1G * 0.5;

    // 1. Concentric Reference Rings
    final ringPaint = Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 0.5G dashed ring
    const dashCount = 36;
    const dashAngle = (2 * pi) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius05G),
        i * dashAngle,
        dashAngle * 0.6,
        false,
        ringPaint,
      );
    }

    // 1.0G solid ring
    canvas.drawCircle(center, radius1G, ringPaint);

    // 2. Crosshairs
    final axisPaint = Paint()
      ..color = const Color(0xFFE5E5EA)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(center.dx - radius1G * 1.1, center.dy), Offset(center.dx + radius1G * 1.1, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius1G * 1.1), Offset(center.dx, center.dy + radius1G * 1.1), axisPaint);

    // 3. Axis Labels
    _drawLabel(canvas, Offset(center.dx + 4, center.dy - radius1G + 3), '1.0G');
    _drawLabel(canvas, Offset(center.dx + 4, center.dy - radius05G + 3), '0.5G');

    _drawAxisTag(canvas, Offset(center.dx, 10), 'ZRYCHLENÍ');
    _drawAxisTag(canvas, Offset(center.dx, size.height - 10), 'BRZDY');
    _drawAxisTag(canvas, Offset(16, center.dy), 'VLEVO');
    _drawAxisTag(canvas, Offset(size.width - 16, center.dy), 'VPRAVO');

    // 4. Scatter Points of Dynamics
    final scatterPaint = Paint()
      ..color = AppTheme.appleBlue.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    for (final pt in scatterPoints) {
      final sx = center.dx + (pt.dx / maxGRange) * (size.width / 2);
      final sy = center.dy - (pt.dy / maxGRange) * (size.width / 2);
      canvas.drawCircle(Offset(sx, sy), 2.2, scatterPaint);
    }

    // 5. Polar Friction Envelope Polygon
    final hasData = envelope.any((r) => r > 0.18);
    if (hasData) {
      final path = Path();
      for (int i = 0; i < 36; i++) {
        final angle = (i * 10) * (pi / 180.0);
        final r = (envelope[i] / maxGRange) * (size.width / 2);
        final x = center.dx + r * cos(angle);
        final y = center.dy - r * sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      // Translucent gradient fill
      final fillPaint = Paint()
        ..color = AppTheme.appleOrange.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Boundary stroke
      final strokePaint = Paint()
        ..color = AppTheme.appleOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, strokePaint);
    }

    // Center jewel
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF1C1C1E));
    canvas.drawCircle(center, 2, Paint()..color = Colors.white);
  }

  void _drawLabel(Canvas canvas, Offset offset, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: AppTheme.appleMutedGray,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawAxisTag(Canvas canvas, Offset center, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: AppTheme.appleMutedGray,
          fontSize: 8.0,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GgFrictionCardPainter oldDelegate) {
    return oldDelegate.maxGRange != maxGRange ||
        oldDelegate.scatterPoints != scatterPoints ||
        oldDelegate.envelope != envelope;
  }
}
