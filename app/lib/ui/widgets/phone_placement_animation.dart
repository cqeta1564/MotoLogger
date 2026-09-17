import 'dart:math';
import 'package:flutter/material.dart';

/// Minimalist line-art / outline vector animation showing a motorcycle fuel tank
/// with its flat top cap, and a smartphone descending smoothly to rest flat on the cap.
/// Strictly Apple design discipline: borderless, pure monochrome grey palette.
class PhonePlacementAnimation extends StatefulWidget {
  final bool isPlaced;

  const PhonePlacementAnimation({
    super.key,
    this.isPlaced = false,
  });

  @override
  State<PhonePlacementAnimation> createState() =>
      _PhonePlacementAnimationState();
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
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isCompleted && !_controller.isAnimating) {
      _controller.forward();
    }
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
    final groundY = size.height - 22.0;

    // Line styles - Pure Apple monochrome grey palette matching BikeUprightAnimation
    final mainPaint = Paint()
      ..color = const Color(0xFF3A3A3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentPaint = Paint()
      ..color = const Color(0xFF8E8E93)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final subtlePaint = Paint()
      ..color = const Color(0xFFC7C7CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    // 1. Ground Reference Line (Horizontální rovina)
    canvas.drawLine(
        Offset(cx - 96, groundY), Offset(cx + 96, groundY), subtlePaint);
    for (double x = cx - 80; x <= cx + 80; x += 16) {
      canvas.drawLine(
          Offset(x, groundY), Offset(x - 4, groundY + 5), subtlePaint);
    }

    // 2. Chassis & Steering Axis references
    // Steering head column rake line (left)
    final steeringTop = Offset(cx - 72, groundY - 78);
    final steeringBottom = Offset(cx - 62, groundY - 14);
    canvas.drawLine(steeringTop, steeringBottom, subtlePaint);
    // Handlebar clamp bracket hint
    canvas.drawLine(
      Offset(steeringTop.dx - 8, steeringTop.dy - 4),
      Offset(steeringTop.dx + 4, steeringTop.dy + 2),
      accentPaint,
    );

    // Frame rail under the tank
    canvas.drawLine(
      Offset(steeringBottom.dx, steeringBottom.dy),
      Offset(cx + 70, groundY - 18),
      subtlePaint,
    );

    // 3. Sculpted Motorcycle Fuel Tank (Boční profil nádrže)
    final deckY = groundY - 68.0; // Flat top plateau deck height
    final tankPath = Path();

    // Start at steering head junction
    tankPath.moveTo(steeringTop.dx + 2, steeringTop.dy + 8);
    // Smooth muscular front rise to the flat top deck
    tankPath.quadraticBezierTo(cx - 48, deckY - 1, cx - 36, deckY);
    // Perfectly flat top deck for fuel cap and phone
    tankPath.lineTo(cx + 36, deckY);
    // Rear slope tapering down towards the rider's seat
    tankPath.quadraticBezierTo(cx + 62, deckY + 4, cx + 80, groundY - 34);
    // Seat junction
    tankPath.lineTo(cx + 76, groundY - 24);
    // Bottom contour line returning forward to the steering head
    tankPath.quadraticBezierTo(
        cx + 10, groundY - 20, steeringBottom.dx + 4, steeringBottom.dy - 6);
    tankPath.close();

    // Fill tank with white to mask background lines
    canvas.drawPath(tankPath, Paint()..color = Colors.white);
    canvas.drawPath(tankPath, mainPaint);

    // Ergonomic knee recess contour line on the tank flank
    final kneePath = Path()
      ..moveTo(cx - 24, deckY + 14)
      ..quadraticBezierTo(cx + 16, deckY + 22, cx + 64, groundY - 28);
    canvas.drawPath(kneePath, accentPaint);

    // Rider seat contour hint behind the tank (right)
    final seatPath = Path()
      ..moveTo(cx + 76, groundY - 24)
      ..quadraticBezierTo(cx + 94, groundY - 30, cx + 114, groundY - 28)
      ..lineTo(cx + 108, groundY - 18)
      ..lineTo(cx + 74, groundY - 20);
    canvas.drawPath(seatPath, subtlePaint);

    // 4. Circular Fuel Tank Cap (Víko nádrže na rovné ploše)
    final capCenter = Offset(cx, deckY);
    final capRect = Rect.fromCenter(center: capCenter, width: 44, height: 8.5);

    // Cap base oval
    canvas.drawOval(capRect, Paint()..color = const Color(0xFFE5E5EA));
    canvas.drawOval(capRect, mainPaint);
    // Cap inner detail ring
    canvas.drawOval(
      Rect.fromCenter(center: capCenter, width: 28, height: 5.5),
      accentPaint,
    );
    // Center keyhole/latch notch
    canvas.drawCircle(capCenter, 1.6, Paint()..color = const Color(0xFF3A3A3C));

    // 5. Smartphone Descent & Placement Animation Dynamics
    // 0.00 -> 0.42: Phone hovers and descends onto the cap
    // 0.42 -> 0.76: Phone rests flat and flush on the cap + contact guide
    // 0.76 -> 1.00: Phone smoothly lifts back up to restart loop
    double phoneY;
    double phoneAlpha = 1.0;
    double contactAlpha = 0.0;
    final restY = deckY - 6.5; // Rests perfectly flush on top of the cap deck

    if (isPlaced) {
      phoneY = restY;
      contactAlpha = 1.0;
    } else if (progress < 0.42) {
      final t = progress / 0.42;
      final ease = 1.0 - pow(1.0 - t, 3.0).toDouble(); // easeOutCubic
      phoneY = (restY - 32) + ease * 32;
    } else if (progress < 0.76) {
      phoneY = restY;
      contactAlpha = 1.0;
    } else {
      final t = (progress - 0.76) / 0.24;
      final ease = pow(t, 2.5).toDouble();
      phoneY = restY - ease * 32;
      phoneAlpha = 1.0 - (0.35 * ease);
    }

    // Downward guidance dashed alignment rays when phone is descending
    if (progress < 0.38 && !isPlaced) {
      final guidePaint = Paint()
        ..color = const Color(0xFF8E8E93).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      for (double dx in [-18.0, 0.0, 18.0]) {
        canvas.drawLine(
          Offset(cx + dx, phoneY + 7),
          Offset(cx + dx, min(phoneY + 16, deckY - 2)),
          guidePaint,
        );
      }
    }

    // Flush contact alignment indicator tick marks when rested
    if (contactAlpha > 0.0) {
      final tickPaint = Paint()
        ..color = const Color(0xFF3A3A3C).withValues(alpha: contactAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      // Left and right flush contact ticks
      canvas.drawLine(
          Offset(cx - 36, deckY - 1), Offset(cx - 32, deckY - 1), tickPaint);
      canvas.drawLine(
          Offset(cx + 32, deckY - 1), Offset(cx + 36, deckY - 1), tickPaint);
    }

    // 6. Smartphone Outline (Phone resting flat on the tank cap)
    final phoneWidth = 58.0;
    final phoneHeight = 11.5;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, phoneY), width: phoneWidth, height: phoneHeight),
      const Radius.circular(3.0),
    );

    // Phone fill and body stroke
    canvas.drawRRect(
        phoneRect, Paint()..color = Colors.white.withValues(alpha: phoneAlpha));
    canvas.drawRRect(
      phoneRect,
      Paint()
        ..color = const Color(0xFF1C1C1E).withValues(alpha: phoneAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Screen glass line
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, phoneY),
          width: phoneWidth - 8,
          height: phoneHeight - 5),
      const Radius.circular(1.8),
    );
    canvas.drawRRect(
      screenRect,
      Paint()
        ..color = const Color(0xFFE5E5EA).withValues(alpha: 0.85 * phoneAlpha),
    );

    // Camera notch on the left
    canvas.drawCircle(
      Offset(cx - 20, phoneY),
      1.4,
      Paint()..color = const Color(0xFF8E8E93).withValues(alpha: phoneAlpha),
    );
  }

  @override
  bool shouldRepaint(covariant _PhonePlacementPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaced != isPlaced;
  }
}
