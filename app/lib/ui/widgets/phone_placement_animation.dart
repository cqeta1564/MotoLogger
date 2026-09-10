import 'dart:math';
import 'package:flutter/material.dart';

/// Minimalist line-art / outline vector animation showing a complete motorcycle
/// parked on its side stand, with a smartphone descending smoothly and
/// resting flat onto the fuel tank cap.
/// Designed to match Apple design discipline: borderless monochrome grey line-art.
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
        return SizedBox(
          width: double.infinity,
          height: 160,
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
    final groundY = size.height - 24.0;

    // Line styles - Pure Apple monochrome grey palette
    final mainPaint = Paint()
      ..color = const Color(0xFF3A3A3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentPaint = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final subtlePaint = Paint()
      ..color = const Color(0xFFC7C7CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // 1. Ground Reference Line (Podkladová rovina)
    canvas.drawLine(Offset(cx - 105, groundY), Offset(cx + 105, groundY), subtlePaint);
    for (double x = cx - 95; x <= cx + 95; x += 16) {
      canvas.drawLine(Offset(x, groundY), Offset(x - 4, groundY + 4), subtlePaint);
    }

    // 2. Wheels & Tires (Obě kola na zemi)
    final tireRadius = 20.0;
    final frontWheelCenter = Offset(cx - 65, groundY - tireRadius);
    final rearWheelCenter = Offset(cx + 62, groundY - tireRadius);

    // Front Wheel
    canvas.drawCircle(frontWheelCenter, tireRadius, Paint()..color = Colors.white);
    canvas.drawCircle(frontWheelCenter, tireRadius, mainPaint);
    canvas.drawCircle(frontWheelCenter, 12.0, subtlePaint);
    canvas.drawCircle(frontWheelCenter, 2.5, Paint()..color = const Color(0xFF48484A));

    // Rear Wheel
    canvas.drawCircle(rearWheelCenter, tireRadius, Paint()..color = Colors.white);
    canvas.drawCircle(rearWheelCenter, tireRadius, mainPaint);
    canvas.drawCircle(rearWheelCenter, 12.0, subtlePaint);
    canvas.drawCircle(rearWheelCenter, 2.5, Paint()..color = const Color(0xFF48484A));
    // Rear sprocket outline
    canvas.drawCircle(rearWheelCenter, 8.0, Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);

    // Front Mudguard / Fender (Přední blatník)
    final fenderPath = Path()
      ..moveTo(frontWheelCenter.dx - 18, groundY - 6)
      ..quadraticBezierTo(frontWheelCenter.dx - 16, groundY - 44, frontWheelCenter.dx + 16, groundY - 30);
    canvas.drawPath(fenderPath, mainPaint);

    // 3. Swingarm & Subframe (Kyvná vidlice a zadní stavba)
    final swingarmPivot = Offset(cx + 14, groundY - 30);
    canvas.drawLine(swingarmPivot, rearWheelCenter, mainPaint..strokeWidth = 2.2);
    mainPaint.strokeWidth = 2.0;
    // Upper subframe strut
    canvas.drawLine(swingarmPivot, Offset(cx + 42, groundY - 50), subtlePaint);

    // 4. Telescopic Inverted Front Forks (Přední vidlice)
    final steeringHead = Offset(cx - 38, groundY - 74);
    // Main fork stanchion
    canvas.drawLine(frontWheelCenter, steeringHead, accentPaint..strokeWidth = 2.0);
    // Parallel slider tube
    canvas.drawLine(
      Offset(frontWheelCenter.dx + 4, frontWheelCenter.dy),
      Offset(steeringHead.dx + 4, steeringHead.dy),
      subtlePaint,
    );

    // 5. Headlight Cowl / Mask (Přední maska)
    final cowlPath = Path()
      ..moveTo(steeringHead.dx, steeringHead.dy)
      ..lineTo(steeringHead.dx - 12, steeringHead.dy + 8)
      ..lineTo(steeringHead.dx - 6, steeringHead.dy + 20)
      ..lineTo(steeringHead.dx + 6, steeringHead.dy + 12);
    canvas.drawPath(cowlPath, subtlePaint);

    // 6. Handlebars & Controls (Řídítka, páčka, zrcátko)
    final barCenter = Offset(steeringHead.dx + 2, steeringHead.dy - 6);
    // Handlebar riser
    canvas.drawLine(barCenter, Offset(barCenter.dx - 10, barCenter.dy - 2), mainPaint);
    // Grip
    canvas.drawLine(
      Offset(barCenter.dx - 10, barCenter.dy - 2),
      Offset(barCenter.dx - 19, barCenter.dy - 2),
      Paint()
        ..color = const Color(0xFF1C1C1E)
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round,
    );
    // Brake lever
    canvas.drawLine(
      Offset(barCenter.dx - 12, barCenter.dy + 1),
      Offset(barCenter.dx - 6, barCenter.dy + 5),
      subtlePaint,
    );
    // Mirror
    canvas.drawLine(barCenter, Offset(barCenter.dx - 8, barCenter.dy - 12), accentPaint);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(barCenter.dx - 8, barCenter.dy - 12), width: 8, height: 5),
      mainPaint,
    );

    // 7. Engine & Trellis Frame Silhouette (Motor a rám)
    final framePath = Path()
      ..moveTo(steeringHead.dx, steeringHead.dy)
      ..lineTo(cx + 8, groundY - 34);
    canvas.drawPath(framePath, subtlePaint);

    // Engine crankcase
    final enginePath = Path()
      ..moveTo(cx - 24, groundY - 36)
      ..lineTo(cx - 6, groundY - 22)
      ..lineTo(cx + 16, groundY - 22)
      ..lineTo(cx + 22, groundY - 34);
    canvas.drawPath(enginePath, subtlePaint);
    canvas.drawCircle(Offset(cx + 4, groundY - 28), 7.0, Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);

    // 8. Side Stand (Boční stojánek opřený pevně o zem)
    final standPivot = Offset(cx - 6, groundY - 28);
    final standFoot = Offset(cx - 22, groundY);
    canvas.drawLine(standPivot, standFoot, mainPaint..strokeWidth = 2.2);
    canvas.drawLine(Offset(standFoot.dx - 4, groundY), Offset(standFoot.dx + 4, groundY), mainPaint);
    mainPaint.strokeWidth = 2.0;

    // 9. Sculpted Motorcycle Fuel Tank (Nádrž s dokonale rovnou plochou)
    final tankPath = Path();
    tankPath.moveTo(steeringHead.dx, steeringHead.dy);
    // Front slope rising up to the flat top deck
    tankPath.quadraticBezierTo(cx - 26, groundY - 82, cx - 18, groundY - 84);
    // Flat top deck for fuel cap and phone
    tankPath.lineTo(cx + 18, groundY - 84);
    // Rear slope tapering down to the seat
    tankPath.quadraticBezierTo(cx + 32, groundY - 80, cx + 40, groundY - 52);
    // Bottom junction line back to steering head
    tankPath.lineTo(cx + 26, groundY - 44);
    tankPath.quadraticBezierTo(cx + 6, groundY - 40, cx - 14, groundY - 44);
    tankPath.lineTo(steeringHead.dx, steeringHead.dy);
    tankPath.close();

    // Fill tank with white to mask frame behind it
    canvas.drawPath(tankPath, Paint()..color = Colors.white);
    canvas.drawPath(tankPath, mainPaint);

    // Ergonomic knee recess crease on the side of the tank
    final kneeCrease = Path()
      ..moveTo(cx - 10, groundY - 74)
      ..quadraticBezierTo(cx + 12, groundY - 68, cx + 26, groundY - 50);
    canvas.drawPath(kneeCrease, accentPaint);

    // 10. Rider's Seat & Tail Cowl (Sedadlo jezdce a zadní krovka)
    final seatPath = Path();
    seatPath.moveTo(cx + 40, groundY - 52);
    seatPath.quadraticBezierTo(cx + 52, groundY - 58, cx + 76, groundY - 54); // Tail
    seatPath.lineTo(cx + 64, groundY - 42); // Undertray
    seatPath.lineTo(cx + 26, groundY - 44);
    canvas.drawPath(seatPath, subtlePaint);
    // Rider seat contour line
    canvas.drawLine(Offset(cx + 36, groundY - 52), Offset(cx + 56, groundY - 52), accentPaint);

    // 11. Circular Fuel Filler Cap (Víko nádrže na rovné ploše)
    final capCenter = Offset(cx, groundY - 84);
    final capRect = Rect.fromCenter(center: capCenter, width: 34, height: 6.5);
    canvas.drawOval(capRect, Paint()..color = const Color(0xFFE5E5EA));
    canvas.drawOval(capRect, mainPaint);
    canvas.drawCircle(capCenter, 1.8, Paint()..color = const Color(0xFF8E8E93));

    // 12. Smartphone Descent & Placement Animation Dynamics
    // 0.00 -> 0.42: Phone hovers and descends onto the cap
    // 0.42 -> 0.76: Phone rests flat and flush on the cap + contact pulse ripples
    // 0.76 -> 1.00: Phone lifts back up to restart cycle
    double phoneY;
    double phoneAlpha = 1.0;
    double pulseScale = 0.0;
    final restY = groundY - 90.0; // Rests flush on the flat tank cap

    if (progress < 0.42) {
      final t = progress / 0.42;
      final ease = 1.0 - pow(1.0 - t, 3.0).toDouble(); // easeOutCubic
      phoneY = (restY - 30) + ease * 30;
    } else if (progress < 0.76) {
      phoneY = restY;
      pulseScale = (progress - 0.42) / 0.34;
    } else {
      final t = (progress - 0.76) / 0.24;
      final ease = pow(t, 2.5).toDouble();
      phoneY = restY - ease * 30;
      phoneAlpha = 1.0 - (0.35 * ease);
    }

    // Concentric contact pulse waves when resting flat on the cap
    if (pulseScale > 0.0) {
      final ringPaint = Paint()
        ..color = const Color(0xFF8E8E93).withValues(alpha: (1.0 - pulseScale) * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawOval(
        Rect.fromCenter(
          center: capCenter,
          width: 34 + pulseScale * 36,
          height: 6.5 + pulseScale * 14,
        ),
        ringPaint,
      );

      if (pulseScale > 0.3) {
        final p2 = (pulseScale - 0.3) / 0.7;
        canvas.drawOval(
          Rect.fromCenter(
            center: capCenter,
            width: 34 + p2 * 28,
            height: 6.5 + p2 * 10,
          ),
          ringPaint..color = const Color(0xFF8E8E93).withValues(alpha: (1.0 - p2) * 0.3),
        );
      }
    }

    // Downward guidance dashed alignment rays when phone is hovering
    if (progress < 0.38) {
      final guideAlpha = (1.0 - (progress / 0.38)).clamp(0.0, 1.0);
      final guidePaint = Paint()
        ..color = const Color(0xFF8E8E93).withValues(alpha: guideAlpha * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      // Downward dashed guide rays connecting phone to landing cap
      double dy = phoneY + 7;
      while (dy < groundY - 84) {
        canvas.drawLine(Offset(cx - 16, dy), Offset(cx - 16, min(dy + 3, groundY - 84)), guidePaint);
        canvas.drawLine(Offset(cx + 16, dy), Offset(cx + 16, min(dy + 3, groundY - 84)), guidePaint);
        dy += 6;
      }

      // Small downward guide arrow
      final arrowY = phoneY + 11;
      final arrowPaint = Paint()
        ..color = const Color(0xFF8E8E93).withValues(alpha: guideAlpha * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(capCenter.dx, arrowY), Offset(capCenter.dx, arrowY + 6), arrowPaint);
      canvas.drawLine(Offset(capCenter.dx - 3, arrowY + 3), Offset(capCenter.dx, arrowY + 6), arrowPaint);
      canvas.drawLine(Offset(capCenter.dx + 3, arrowY + 3), Offset(capCenter.dx, arrowY + 6), arrowPaint);
    }

    // 13. Smartphone (iPhone outline laying flat on cap)
    final phoneWidth = 50.0;
    final phoneHeight = 11.0;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(capCenter.dx, phoneY), width: phoneWidth, height: phoneHeight),
      const Radius.circular(3.5),
    );

    // Phone body fill and outline
    canvas.drawRRect(phoneRect, Paint()..color = Colors.white.withValues(alpha: phoneAlpha));
    canvas.drawRRect(
      phoneRect,
      Paint()
        ..color = const Color(0xFF1C1C1E).withValues(alpha: phoneAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Camera bump / notch accent on top
    final camRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(capCenter.dx - 16, phoneY - 3), width: 7, height: 3.5),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(camRect, Paint()..color = const Color(0xFF8E8E93).withValues(alpha: phoneAlpha));

    // Screen display surface
    final screenRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(capCenter.dx, phoneY), width: phoneWidth - 8, height: phoneHeight - 5),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      screenRRect,
      Paint()..color = const Color(0xFFE5E5EA).withValues(alpha: 0.85 * phoneAlpha),
    );

    // 14. Subtle uppercase instruction caption at bottom
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'POLOŽTE TELEFON PLOCHOU NA VÍKO NÁDRŽE',
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Color(0xFF8E8E93),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(cx - labelPainter.width / 2, size.height - 18));
  }

  @override
  bool shouldRepaint(covariant _PhonePlacementPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaced != isPlaced;
  }
}
