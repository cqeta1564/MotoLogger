import 'dart:math';
import 'package:flutter/material.dart';

/// Minimalist line-art / outline vector animation showing a motorcycle
/// tilting from its side stand into a perfectly balanced 0.0° vertical/upright position.
/// Matches the Apple design aesthetic and line weight of PhonePlacementAnimation.
class BikeUprightAnimation extends StatefulWidget {
  final bool isUpright;

  const BikeUprightAnimation({
    super.key,
    this.isUpright = false,
  });

  @override
  State<BikeUprightAnimation> createState() => _BikeUprightAnimationState();
}

class _BikeUprightAnimationState extends State<BikeUprightAnimation>
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
            painter: _BikeUprightPainter(
              progress: _controller.value,
              isUpright: widget.isUpright,
            ),
          ),
        );
      },
    );
  }
}

class _BikeUprightPainter extends CustomPainter {
  final double progress;
  final bool isUpright;

  _BikeUprightPainter({
    required this.progress,
    required this.isUpright,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.52;
    final groundY = cy + 42.0;

    // Line paints - Pure Apple monochrome grey palette
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

    // 1. Static Ground Reference Line (Horizontální rovina)
    canvas.drawLine(Offset(cx - 96, groundY), Offset(cx + 96, groundY), subtlePaint);
    for (double x = cx - 80; x <= cx + 80; x += 16) {
      canvas.drawLine(Offset(x, groundY), Offset(x - 4, groundY + 5), subtlePaint);
    }

    // 2. Animation Phases:
    // 0.00 -> 0.42: Tilts from -13.5° (side stand) to 0.0° (upright)
    // 0.42 -> 0.76: Holds steady at 0.0° vertical with laser guide & pulse
    // 0.76 -> 1.00: Smoothly tilts back to -13.5° to seamlessly restart loop
    double currentLeanDeg;
    double alignmentAlpha = 0.0;
    double pulseScale = 0.0;

    if (progress < 0.42) {
      final t = progress / 0.42;
      final ease = 1.0 - pow(1.0 - t, 3.0).toDouble(); // easeOutCubic
      currentLeanDeg = -13.5 * (1.0 - ease);
      if (t > 0.8) {
        alignmentAlpha = (t - 0.8) / 0.2;
      }
    } else if (progress < 0.76) {
      currentLeanDeg = 0.0;
      alignmentAlpha = 1.0;
      pulseScale = (progress - 0.42) / 0.34;
    } else {
      final t = (progress - 0.76) / 0.24;
      final ease = pow(t, 2.5).toDouble();
      currentLeanDeg = -13.5 * ease;
      alignmentAlpha = (1.0 - t).clamp(0.0, 1.0);
    }

    final currentLeanRad = currentLeanDeg * (pi / 180.0);

    // 3. Static Vertical 0° Laser / Plumb Plumb-Line Guide
    final plumbPaint = Paint()
      ..color = const Color(0xFF8E8E93).withValues(alpha: 0.25 + 0.65 * alignmentAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Vertical dashed plumb line through center
    double dashY = groundY - 116;
    while (dashY < groundY + 4) {
      canvas.drawLine(Offset(cx, dashY), Offset(cx, min(dashY + 5, groundY + 4)), plumbPaint);
      dashY += 9;
    }

    // Top vertical alignment marker notch
    if (alignmentAlpha > 0.0) {
      final notchPaint = Paint()
        ..color = const Color(0xFF48484A).withValues(alpha: alignmentAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(cx, groundY - 120), Offset(cx, groundY - 112), notchPaint);
      canvas.drawLine(Offset(cx - 4, groundY - 116), Offset(cx, groundY - 112), notchPaint);
      canvas.drawLine(Offset(cx + 4, groundY - 116), Offset(cx, groundY - 112), notchPaint);
    }

    // Expanding alignment confirmation pulse when bike reaches 0.0°
    if (pulseScale > 0.0) {
      final pulsePaint = Paint()
        ..color = const Color(0xFF8E8E93).withValues(alpha: (1.0 - pulseScale) * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, groundY - 60), 16.0 + pulseScale * 24.0, pulsePaint);
    }

    // 4. Draw Motorcycle Front Profile (Rotated around front tire contact patch)
    canvas.save();
    canvas.translate(cx, groundY);
    canvas.rotate(currentLeanRad);
    canvas.translate(-cx, -groundY);

    // 4a. Front Tire & Wheel
    final tireRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, groundY - 22), width: 18, height: 44),
      const Radius.circular(9),
    );
    // Tire white fill to mask background
    canvas.drawRRect(tireRect, Paint()..color = Colors.white);
    canvas.drawRRect(tireRect, mainPaint);

    // Inner rim line
    final rimRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, groundY - 22), width: 8, height: 26),
      const Radius.circular(4),
    );
    canvas.drawRRect(rimRect, subtlePaint);
    // Front axle hub
    canvas.drawCircle(Offset(cx, groundY - 22), 2.5, Paint()..color = const Color(0xFF48484A));

    // 4b. Front Mudguard / Fender (Přední blatník)
    final fenderPath = Path()
      ..moveTo(cx - 13, groundY - 38)
      ..quadraticBezierTo(cx, groundY - 48, cx + 13, groundY - 38);
    canvas.drawPath(fenderPath, mainPaint);

    // 4c. Telescopic Inverted Front Forks (Přední vidlice)
    canvas.drawLine(Offset(cx - 14, groundY - 22), Offset(cx - 12, groundY - 66), accentPaint);
    canvas.drawLine(Offset(cx + 14, groundY - 22), Offset(cx + 12, groundY - 66), accentPaint);

    // 4d. Front Cowl / Headlight Mask (Maska a světlomet)
    final cowlPath = Path()
      ..moveTo(cx - 22, groundY - 62)
      ..lineTo(cx - 16, groundY - 78)
      ..lineTo(cx + 16, groundY - 78)
      ..lineTo(cx + 22, groundY - 62)
      ..lineTo(cx, groundY - 54)
      ..close();
    canvas.drawPath(cowlPath, Paint()..color = Colors.white);
    canvas.drawPath(cowlPath, mainPaint);

    // DRL / Headlight LED signature lines
    canvas.drawLine(Offset(cx - 12, groundY - 63), Offset(cx - 4, groundY - 60), accentPaint);
    canvas.drawLine(Offset(cx + 12, groundY - 63), Offset(cx + 4, groundY - 60), accentPaint);

    // 4e. Aerodynamic Windscreen (Štítek)
    final screenPath = Path()
      ..moveTo(cx - 12, groundY - 78)
      ..quadraticBezierTo(cx, groundY - 96, cx + 12, groundY - 78);
    canvas.drawPath(
      screenPath,
      Paint()
        ..color = const Color(0xFF8E8E93)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // 4f. Handlebars & Grips (Řídítka)
    final barY = groundY - 75.0;
    canvas.drawLine(Offset(cx - 44, barY + 2), Offset(cx + 44, barY + 2), mainPaint);
    // Grips & bar ends
    canvas.drawLine(Offset(cx - 48, barY + 2), Offset(cx - 44, barY + 2), Paint()
      ..color = const Color(0xFF1C1C1E)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(cx + 44, barY + 2), Offset(cx + 48, barY + 2), Paint()
      ..color = const Color(0xFF1C1C1E)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round);
    // Levers (brzdová a spojková páčka)
    canvas.drawLine(Offset(cx - 42, barY + 5), Offset(cx - 28, barY + 7), subtlePaint);
    canvas.drawLine(Offset(cx + 42, barY + 5), Offset(cx + 28, barY + 7), subtlePaint);

    // 4g. Sleek Mirrors / Aero Winglets
    canvas.drawLine(Offset(cx - 24, groundY - 76), Offset(cx - 46, groundY - 88), accentPaint);
    canvas.drawLine(Offset(cx - 46, groundY - 88), Offset(cx - 40, groundY - 92), mainPaint);
    canvas.drawLine(Offset(cx + 24, groundY - 76), Offset(cx + 46, groundY - 88), accentPaint);
    canvas.drawLine(Offset(cx + 46, groundY - 88), Offset(cx + 40, groundY - 92), mainPaint);

    // 4h. Side Stand (Boční stojánek na levé straně)
    // When bike leans left (-13.5°), the stand tip reaches down to touch the ground.
    // When bike rights up to 0°, the stand rises off the ground.
    final standPath = Path()
      ..moveTo(cx - 10, groundY - 32)
      ..lineTo(cx - 32, groundY - 6)
      ..lineTo(cx - 36, groundY - 6);
    canvas.drawPath(
      standPath,
      Paint()
        ..color = const Color(0xFF8E8E93)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();

    // 5. Angle badge when locked at 0°
    if (alignmentAlpha > 0.0) {
      final badgePainter = TextPainter(
        text: TextSpan(
          text: currentLeanDeg.abs() < 0.2 ? '0.0°' : '${currentLeanDeg.toStringAsFixed(1)}°',
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: const Color(0xFF48484A).withValues(alpha: alignmentAlpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      badgePainter.paint(canvas, Offset(cx - badgePainter.width / 2, groundY - 128));
    }
  }

  @override
  bool shouldRepaint(covariant _BikeUprightPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isUpright != isUpright;
  }
}
