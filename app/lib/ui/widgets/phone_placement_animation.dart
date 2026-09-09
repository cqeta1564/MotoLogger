import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Minimalist line-art / outline vector animation showing a smartphone
/// descending and resting directly onto the flat fuel tank cap of a motorcycle.
class PhonePlacementAnimation extends StatefulWidget {
  final bool isPlaced;

  const PhonePlacementAnimation({
    super.key,
    this.isPlaced = false,
  });

  @override
  State<PhonePlacementAnimation> createState() => _PhonePlacementAnimationState();
}

class _PhonePlacementAnimationState extends State<PhonePlacementAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
        return Container(
          width: double.infinity,
          height: 190,
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.2,
            ),
          ),
          child: CustomPaint(
            painter: _PhonePlacementPainter(
              progress: _controller.value,
              isPlaced: widget.isPlaced,
            ),
          ),
        );
      },
    );
  }
}

class _PhonePlacementPainter extends CustomPainter {
  final double progress;
  final bool isPlaced;

  _PhonePlacementPainter({
    required this.progress,
    required this.isPlaced,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.55;

    // Line styles
    final outlinePaint = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final capPaint = Paint()
      ..color = CupertinoColors.systemCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final phonePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // 1. Draw Motorcycle Outline (Handlebars + Muscular Tank + Seat start)
    final tankPath = Path();
    // Start at front steering head
    tankPath.moveTo(cx - 110, cy - 8);
    tankPath.quadraticBezierTo(cx - 95, cy - 36, cx - 60, cy - 40); // Front slope
    // Tank top ridge
    tankPath.lineTo(cx - 28, cy - 40);
    // Flat tank cap indentation
    tankPath.lineTo(cx + 28, cy - 40);
    // Rear slope down to seat
    tankPath.quadraticBezierTo(cx + 65, cy - 36, cx + 85, cy - 5);
    // Pillion / seat start
    tankPath.quadraticBezierTo(cx + 105, cy + 5, cx + 120, cy + 12);

    // Subtle tank body under-line
    final underTankPath = Path()
      ..moveTo(cx - 100, cy + 16)
      ..quadraticBezierTo(cx - 40, cy + 32, cx + 70, cy + 22);

    canvas.drawPath(tankPath, outlinePaint);
    canvas.drawPath(
      underTankPath,
      Paint()
        ..color = const Color(0xFF3A3A3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Handlebar & fork hint at front
    final forkPaint = Paint()
      ..color = const Color(0xFF48484A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 110, cy - 8), Offset(cx - 128, cy + 28), forkPaint);
    canvas.drawLine(Offset(cx - 106, cy - 22), Offset(cx - 120, cy - 34), forkPaint);

    // 2. Flat Tank Cap (Víko nádrže)
    final capCenter = Offset(cx, cy - 40);
    final capRect = Rect.fromCenter(center: capCenter, width: 44, height: 8);
    canvas.drawOval(
      capRect,
      Paint()..color = const Color(0xFF2C2C2E),
    );
    canvas.drawOval(capRect, capPaint);
    canvas.drawCircle(capCenter, 2.5, Paint()..color = CupertinoColors.systemCyan);

    // 3. Animation cycle of phone descending onto cap
    // Progress:
    // 0.0 -> 0.45: Hover and descend
    // 0.45 -> 0.75: Resting flat on the cap + pulse waves
    // 0.75 -> 1.0: Lift back up gently to restart loop
    double phoneY;
    double phoneAlpha = 1.0;
    double pulseScale = 0.0;

    if (progress < 0.45) {
      // Descending with easeOutCubic
      final t = progress / 0.45;
      final ease = 1 - pow(1 - t, 3).toDouble();
      phoneY = (cy - 92) + ease * 44; // From -92 down to -48 (rests on cap)
    } else if (progress < 0.75) {
      // Resting on cap
      phoneY = cy - 48;
      pulseScale = (progress - 0.45) / 0.30;
    } else {
      // Lifting back up
      final t = (progress - 0.75) / 0.25;
      final ease = pow(t, 2).toDouble();
      phoneY = (cy - 48) - ease * 44;
      phoneAlpha = 1.0 - (0.4 * ease);
    }

    // Contact pulse rings when phone touches the cap
    if (pulseScale > 0.0) {
      final ringPaint = Paint()
        ..color = CupertinoColors.systemCyan.withValues(alpha: (1.0 - pulseScale) * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawOval(
        Rect.fromCenter(
          center: capCenter,
          width: 44 + pulseScale * 38,
          height: 8 + pulseScale * 14,
        ),
        ringPaint,
      );
    }

    // 4. Smartphone outline
    final phoneWidth = 62.0;
    final phoneHeight = 14.0;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, phoneY), width: phoneWidth, height: phoneHeight),
      const Radius.circular(4),
    );

    // Phone fill and stroke
    canvas.drawRRect(
      phoneRect,
      Paint()..color = const Color(0xFF1C1C1E).withValues(alpha: phoneAlpha),
    );
    canvas.drawRRect(
      phoneRect,
      phonePaint..color = Colors.white.withValues(alpha: phoneAlpha),
    );

    // Glowing screen indicator
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, phoneY), width: phoneWidth - 10, height: phoneHeight - 6),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      screenRect,
      Paint()..color = CupertinoColors.systemCyan.withValues(alpha: 0.85 * phoneAlpha),
    );

    // Camera bump / notch dot
    canvas.drawCircle(
      Offset(cx - 20, phoneY),
      1.5,
      Paint()..color = Colors.white.withValues(alpha: phoneAlpha),
    );

    // Downward guidance arrow when phone is hovering
    if (progress < 0.40) {
      final arrowAlpha = (1.0 - (progress / 0.40)).clamp(0.0, 1.0);
      final arrowPaint = Paint()
        ..color = CupertinoColors.systemCyan.withValues(alpha: arrowAlpha * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final arrowY = phoneY + 16;
      canvas.drawLine(Offset(cx, arrowY), Offset(cx, arrowY + 10), arrowPaint);
      canvas.drawLine(Offset(cx - 4, arrowY + 6), Offset(cx, arrowY + 10), arrowPaint);
      canvas.drawLine(Offset(cx + 4, arrowY + 6), Offset(cx, arrowY + 10), arrowPaint);
    }

    // Instructional label at bottom
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'POLOŽTE TELEFON PLOCHOU NA VÍKO NÁDRŽE',
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Colors.white54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(cx - labelPainter.width / 2, size.height - 22));
  }

  @override
  bool shouldRepaint(covariant _PhonePlacementPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaced != isPlaced;
  }
}
