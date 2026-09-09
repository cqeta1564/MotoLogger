import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Apple HIG style vector illustration of a motorcycle resting on its side stand
/// with a smartphone resting flat on the fuel tank cap, and animated wireless
/// calibration sync pulses communicating with the under-seat ESP unit.
class MotorcycleTankIllustration extends StatefulWidget {
  final double leanAngleDeg;
  final bool isCalibrated;
  final bool isStable;

  const MotorcycleTankIllustration({
    super.key,
    required this.leanAngleDeg,
    this.isCalibrated = false,
    this.isStable = false,
  });

  @override
  State<MotorcycleTankIllustration> createState() => _MotorcycleTankIllustrationState();
}

class _MotorcycleTankIllustrationState extends State<MotorcycleTankIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 240,
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: widget.isStable
                  ? CupertinoColors.activeGreen.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isStable
                    ? CupertinoColors.activeGreen.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Vector illustration painter
              Positioned.fill(
                child: CustomPaint(
                  painter: _MotorcycleIllustrationPainter(
                    leanAngleDeg: widget.leanAngleDeg,
                    pulseProgress: _pulseController.value,
                    isCalibrated: widget.isCalibrated,
                    isStable: widget.isStable,
                  ),
                ),
              ),

              // Angle badge overlay (top right)
              Positioned(
                top: 14,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.isStable
                          ? CupertinoColors.activeGreen.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isStable ? Icons.check_circle : Icons.tune_rounded,
                        size: 13,
                        color: widget.isStable
                            ? CupertinoColors.activeGreen
                            : CupertinoColors.systemCyan,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.leanAngleDeg.abs().toStringAsFixed(1)}° ${widget.leanAngleDeg < 0 ? "vlevo" : widget.leanAngleDeg > 0 ? "vpravo" : "střed"}',
                        style: TextStyle(
                          fontFamily: '.SF Pro Display',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.isStable
                              ? CupertinoColors.activeGreen
                              : Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Status pill (top left)
              Positioned(
                top: 14,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isStable
                              ? CupertinoColors.activeGreen
                              : CupertinoColors.activeOrange,
                          boxShadow: [
                            BoxShadow(
                              color: widget.isStable
                                  ? CupertinoColors.activeGreen.withValues(alpha: 0.6)
                                  : CupertinoColors.activeOrange.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.isStable ? 'PŘIPRAVENO' : 'USTALUJI...',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: widget.isStable
                              ? CupertinoColors.activeGreen
                              : Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MotorcycleIllustrationPainter extends CustomPainter {
  final double leanAngleDeg;
  final double pulseProgress;
  final bool isCalibrated;
  final bool isStable;

  _MotorcycleIllustrationPainter({
    required this.leanAngleDeg,
    required this.pulseProgress,
    required this.isCalibrated,
    required this.isStable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.48;
    final groundY = size.height - 32.0;

    // 1. Draw subtle ground grid and contact lines
    _drawGround(canvas, size, groundY);

    // 2. Center plumb line (vertical reference 0°)
    _drawPlumbLine(canvas, cx, groundY);

    // Dynamic tilt angle clamped visually for illustration clarity (-25° to +25°)
    // Real bike on side stand is usually -10° to -16°.
    final displayTiltDeg = leanAngleDeg.clamp(-25.0, 25.0);
    final tiltRad = displayTiltDeg * pi / 180.0;

    // Pivot around motorcycle tire ground contact point
    canvas.save();
    canvas.translate(cx, groundY);
    canvas.rotate(tiltRad);

    // 3. Draw Side Stand (kickstand extends to the left ground)
    _drawKickstand(canvas, groundY);

    // 4. Draw Motorcycle Silhouette & Frame (Rear 3/4 perspective)
    _drawMotorcycleBody(canvas);

    // 5. Draw ESP Telemetry Unit under the seat
    final espPos = const Offset(10, -78);
    _drawEspUnit(canvas, espPos);

    // 6. Draw Fuel Tank & Flat Tank Cap
    final tankCapPos = const Offset(-2, -142);
    _drawTankAndCap(canvas, tankCapPos);

    // 7. Draw Smartphone resting flat on the tank cap
    final phonePos = const Offset(-2, -150);
    _drawSmartphone(canvas, phonePos);

    // 8. Draw Animated Wireless BLE Calibration Sync Arc between Phone and ESP
    _drawBleSyncBeam(canvas, phonePos, espPos);

    canvas.restore();

    // 9. Draw lean angle indicator arc on the canvas
    _drawAngleArc(canvas, cx, groundY, tiltRad, displayTiltDeg);
  }

  void _drawGround(Canvas canvas, Size size, double groundY) {
    final groundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(20, groundY), Offset(size.width - 20, groundY), groundPaint);

    // Ground tick marks / dashed surface
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    for (double x = 30; x < size.width - 20; x += 16) {
      canvas.drawLine(Offset(x, groundY + 1), Offset(x - 8, groundY + 9), tickPaint);
    }
  }

  void _drawPlumbLine(Canvas canvas, double cx, double groundY) {
    final plumbPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed plumb line (true vertical 0°)
    const dashHeight = 5.0;
    const dashSpace = 4.0;
    double startY = groundY - 170;
    while (startY < groundY) {
      canvas.drawLine(
        Offset(cx, startY),
        Offset(cx, min(startY + dashHeight, groundY)),
        plumbPaint,
      );
      startY += dashHeight + dashSpace;
    }

    // 0° label on top of plumb line
    final tp = TextPainter(
      text: TextSpan(
        text: '0°',
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, groundY - 184));
  }

  void _drawKickstand(Canvas canvas, double groundY) {
    final standPaint = Paint()
      ..color = const Color(0xFF8E8E93)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final footPaint = Paint()
      ..color = const Color(0xFFAEB0B6)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    // Kickstand originates near swingarm pivot and reaches out to the left
    canvas.drawLine(const Offset(-12, -45), const Offset(-52, -2), standPaint);
    canvas.drawLine(const Offset(-58, -1), const Offset(-46, -1), footPaint);

    // Kickstand sensor / bracket dot
    canvas.drawCircle(const Offset(-12, -45), 3.0, Paint()..color = const Color(0xFF48484A));
  }

  void _drawMotorcycleBody(Canvas canvas) {
    // Rear tire (ground contact)
    final tirePaint = Paint()
      ..color = const Color(0xFF1C1C1E)
      ..style = PaintingStyle.fill;
    final tireRimPaint = Paint()
      ..color = const Color(0xFF3A3A3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final tireRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, -28), width: 34, height: 56),
      const Radius.circular(16),
    );
    canvas.drawRRect(tireRect, tirePaint);
    canvas.drawRRect(tireRect, tireRimPaint);

    // Rim inner hub
    canvas.drawCircle(const Offset(0, -28), 9, Paint()..color = const Color(0xFF2C2C2E));
    canvas.drawCircle(const Offset(0, -28), 3.5, Paint()..color = const Color(0xFF636366));

    // Swingarm & Chain drive
    final armPaint = Paint()
      ..color = const Color(0xFF48484A)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0, -28), const Offset(-18, -58), armPaint);
    canvas.drawLine(const Offset(0, -28), const Offset(18, -58), armPaint);

    // Tail section and pillion seat
    final tailPath = Path()
      ..moveTo(-18, -65)
      ..lineTo(-24, -92)
      ..quadraticBezierTo(-18, -108, 0, -112)
      ..quadraticBezierTo(18, -108, 24, -92)
      ..lineTo(18, -65)
      ..close();

    canvas.drawPath(
      tailPath,
      Paint()..color = const Color(0xFF242426),
    );
    canvas.drawPath(
      tailPath,
      Paint()
        ..color = const Color(0xFF48484A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Sleek rear taillight strip (Red glow)
    final tailLightPaint = Paint()
      ..color = const Color(0xFFFF453A).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-14, -96), const Offset(14, -96), tailLightPaint);

    // Exhaust pipe (right side)
    final exhaustPath = Path()
      ..moveTo(14, -40)
      ..lineTo(28, -52)
      ..lineTo(26, -58)
      ..lineTo(12, -44)
      ..close();
    canvas.drawPath(exhaustPath, Paint()..color = const Color(0xFF5A5A5F));
  }

  void _drawTankAndCap(Canvas canvas, Offset capPos) {
    // Fuel tank main muscular shape
    final tankPath = Path()
      ..moveTo(-26, -110)
      ..quadraticBezierTo(-34, -132, -20, -145)
      ..quadraticBezierTo(-10, -150, 0, -150)
      ..quadraticBezierTo(10, -150, 20, -145)
      ..quadraticBezierTo(34, -132, 26, -110)
      ..close();

    // Dark sleek titanium tank fill
    canvas.drawPath(
      tankPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A3C), Color(0xFF1F1F21)],
        ).createShader(Rect.fromLTWH(-34, -150, 68, 45)),
    );

    // Tank highlight outline
    canvas.drawPath(
      tankPath,
      Paint()
        ..color = const Color(0xFF636366)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Flat Fuel Cap ("Víko nádrže")
    final capRect = Rect.fromCenter(center: capPos, width: 28, height: 7.5);
    canvas.drawOval(
      capRect,
      Paint()..color = const Color(0xFF48484A),
    );
    canvas.drawOval(
      capRect,
      Paint()
        ..color = CupertinoColors.systemCyan.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Center keyhole / aircraft latch detail
    canvas.drawCircle(capPos, 2.0, Paint()..color = const Color(0xFF8E8E93));
  }

  void _drawSmartphone(Canvas canvas, Offset phonePos) {
    // Smartphone lying flat horizontally across the flat tank cap
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: phonePos, width: 44, height: 11),
      const Radius.circular(3.5),
    );

    // Phone casing (iPhone dark titanium frame)
    canvas.drawRRect(
      phoneRect,
      Paint()..color = const Color(0xFF0A84FF),
    );
    canvas.drawRRect(
      phoneRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Phone screen neon glow (Apple blue / green)
    final screenColor = isStable ? CupertinoColors.activeGreen : CupertinoColors.systemCyan;
    final screenPaint = Paint()
      ..color = screenColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final innerScreen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: phonePos, width: 38, height: 7),
      const Radius.circular(2),
    );
    canvas.drawRRect(innerScreen, screenPaint);

    // Dynamic island / sensor dot in center of phone
    canvas.drawCircle(phonePos, 1.2, Paint()..color = Colors.black);

    // Glowing aura around phone
    canvas.drawRRect(
      phoneRect,
      Paint()
        ..color = screenColor.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6.0),
    );
  }

  void _drawEspUnit(Canvas canvas, Offset espPos) {
    // ESP unit mounted under the seat
    final espRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: espPos, width: 20, height: 13),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      espRect,
      Paint()..color = const Color(0xFF1C1C1E),
    );
    canvas.drawRRect(
      espRect,
      Paint()
        ..color = const Color(0xFF30D158)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Flashing status LED on ESP
    final ledAlpha = (sin(pulseProgress * 2 * pi) + 1.0) / 2.0;
    final ledPaint = Paint()
      ..color = CupertinoColors.activeGreen.withValues(alpha: 0.3 + 0.7 * ledAlpha);
    canvas.drawCircle(espPos.translate(-4, 0), 2.0, ledPaint);
  }

  void _drawBleSyncBeam(Canvas canvas, Offset start, Offset end) {
    // Animated glowing wireless data stream between phone and ESP unit
    final beamPaint = Paint()
      ..color = CupertinoColors.systemCyan.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final wavePath = Path();
    wavePath.moveTo(start.dx, start.dy + 6);

    final controlPoint = Offset((start.dx + end.dx) / 2 - 12, (start.dy + end.dy) / 2);
    wavePath.quadraticBezierTo(controlPoint.dx, controlPoint.dy, end.dx, end.dy - 6);

    canvas.drawPath(wavePath, beamPaint);

    // Animated packet dot traveling along the curve
    final t = pulseProgress;
    final u = 1 - t;
    final px = u * u * start.dx + 2 * u * t * controlPoint.dx + t * t * end.dx;
    final py = u * u * (start.dy + 6) + 2 * u * t * controlPoint.dy + t * t * (end.dy - 6);

    canvas.drawCircle(
      Offset(px, py),
      3.0,
      Paint()
        ..color = CupertinoColors.systemCyan
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.0),
    );
  }

  void _drawAngleArc(
    Canvas canvas,
    double cx,
    double groundY,
    double tiltRad,
    double tiltDeg,
  ) {
    if (tiltDeg.abs() < 0.5) return;

    final arcRadius = 110.0;
    final arcRect = Rect.fromCircle(center: Offset(cx, groundY), radius: arcRadius);

    final arcPaint = Paint()
      ..color = isStable
          ? CupertinoColors.activeGreen.withValues(alpha: 0.7)
          : CupertinoColors.systemCyan.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Arc starts from vertical (-pi/2) to tilted angle (-pi/2 + tiltRad)
    const startAngle = -pi / 2;
    canvas.drawArc(arcRect, startAngle, tiltRad, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _MotorcycleIllustrationPainter oldDelegate) {
    return oldDelegate.leanAngleDeg != leanAngleDeg ||
        oldDelegate.pulseProgress != pulseProgress ||
        oldDelegate.isCalibrated != isCalibrated ||
        oldDelegate.isStable != isStable;
  }
}
