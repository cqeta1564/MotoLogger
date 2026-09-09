import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Authentic, humorous yellow construction / builder's spirit level ("Zednická vodováha").
/// Features a classic yellow extruded beam, rubber end bumpers, metric ruler ticks,
/// and a fluorescent green acrylic vial with a free-floating fluid air bubble.
class ConstructionSpiritLevelWidget extends StatefulWidget {
  final ValueChanged<double>? onAngleChanged;
  final ValueChanged<bool>? onStabilityChanged;
  final double? simulatedRollDeg;

  const ConstructionSpiritLevelWidget({
    super.key,
    this.onAngleChanged,
    this.onStabilityChanged,
    this.simulatedRollDeg,
  });

  @override
  State<ConstructionSpiritLevelWidget> createState() => _ConstructionSpiritLevelWidgetState();
}

class _ConstructionSpiritLevelWidgetState extends State<ConstructionSpiritLevelWidget> {
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _currentRollDeg = 0.0;
  double _filteredRollDeg = 0.0;
  bool _isStable = false;
  final List<double> _recentRolls = [];
  Timer? _simTimer;

  static const double _filterK = 0.22;

  double get currentRollDeg => _filteredRollDeg;
  bool get isStable => _isStable;

  @override
  void initState() {
    super.initState();
    _startSensorListener();
  }

  void _startSensorListener() {
    if (widget.simulatedRollDeg != null) {
      _currentRollDeg = widget.simulatedRollDeg!;
      _filteredRollDeg = widget.simulatedRollDeg!;
      _isStable = true;
      widget.onAngleChanged?.call(_filteredRollDeg);
      widget.onStabilityChanged?.call(true);
      return;
    }

    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 20),
      ).listen(
        _onAccelerometerEvent,
        onError: (_) => _fallbackSimulation(),
      );
    } catch (_) {
      _fallbackSimulation();
    }
  }

  void _fallbackSimulation() {
    _simTimer?.cancel();
    double baseAngle = -12.4;
    int tick = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      tick++;
      final noise = tick > 25 ? 0.0 : sin(tick * 0.4) * 0.25;
      _updateAngle(baseAngle + noise);
    });
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final ax = event.x;
    final ay = event.y;
    final az = event.z;

    // Roll tilt in degrees
    final roll = -atan2(ax, sqrt(ay * ay + az * az)) * (180.0 / pi);
    _updateAngle(roll);
  }

  void _updateAngle(double roll) {
    if (!mounted) return;

    setState(() {
      _currentRollDeg = roll;
      _filteredRollDeg = _filteredRollDeg * (1.0 - _filterK) + _currentRollDeg * _filterK;
      _evaluateStability(_filteredRollDeg);
    });

    widget.onAngleChanged?.call(_filteredRollDeg);
  }

  void _evaluateStability(double roll) {
    _recentRolls.add(roll);
    if (_recentRolls.length > 25) {
      _recentRolls.removeAt(0);
    }

    if (_recentRolls.length >= 20) {
      double minRoll = _recentRolls.reduce(min);
      double maxRoll = _recentRolls.reduce(max);
      final delta = maxRoll - minRoll;

      final newlyStable = delta < 0.25;
      if (newlyStable != _isStable) {
        _isStable = newlyStable;
        if (_isStable) {
          HapticFeedback.selectionClick();
        }
        widget.onStabilityChanged?.call(_isStable);
      }
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Humorous builder status tagline
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (_isStable) {
      statusText = 'Na milimetr přesně! V lajně. 🎯';
      statusColor = CupertinoColors.activeGreen;
      statusIcon = Icons.check_circle_rounded;
    } else if (_filteredRollDeg.abs() > 20.0) {
      statusText = 'Křivý jak šavle! Položte na nádrž.';
      statusColor = CupertinoColors.systemYellow;
      statusIcon = Icons.handyman_rounded;
    } else {
      statusText = 'Ustaluji bublinu v libele...';
      statusColor = Colors.white70;
      statusIcon = Icons.hourglass_top_rounded;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The Classic Builder's Spirit Level
        Container(
          width: double.infinity,
          height: 86,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              size: const Size(double.infinity, 86),
              painter: _ConstructionLevelPainter(
                rollDeg: _filteredRollDeg,
                isStable: _isStable,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Builder's humorous status badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _isStable
                ? CupertinoColors.activeGreen.withValues(alpha: 0.15)
                : const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isStable
                  ? CupertinoColors.activeGreen.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 15, color: statusColor),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConstructionLevelPainter extends CustomPainter {
  final double rollDeg;
  final bool isStable;

  _ConstructionLevelPainter({
    required this.rollDeg,
    required this.isStable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw Bright Yellow Extruded Aluminum Body
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFDD00), // Bright tool yellow highlight
          Color(0xFFFFC000), // Deep rich construction yellow
          Color(0xFFE5A800), // Base bevel
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(10),
    );
    canvas.drawRRect(bodyRRect, bodyPaint);

    // Bevel edges (aluminum top edge light and bottom shadow)
    final topBevel = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(16, 2), Offset(w - 16, 2), topBevel);

    final bottomBevel = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(16, h - 2), Offset(w - 16, h - 2), bottomBevel);

    // 2. Metric Ruler Markings along top edge
    final rulerPaint = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = 1.0;

    for (double x = 32; x < w - 32; x += 6) {
      final isMajor = ((x - 32) % 30).abs() < 1;
      final isMedium = ((x - 32) % 12).abs() < 1;
      final markH = isMajor ? 8.0 : (isMedium ? 5.0 : 3.0);
      canvas.drawLine(Offset(x, 2), Offset(x, 2 + markH), rulerPaint);
    }

    // 3. Black Heavy-Duty Rubber End Bumpers (left and right)
    final bumperPaint = Paint()..color = const Color(0xFF1F1F21);
    final bumperHighlight = Paint()..color = const Color(0xFF38383A);

    // Left bumper
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, 22, h),
        topLeft: const Radius.circular(10),
        bottomLeft: const Radius.circular(10),
      ),
      bumperPaint,
    );
    canvas.drawLine(const Offset(22, 0), Offset(22, h), bumperHighlight);

    // Right bumper
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w - 22, 0, 22, h),
        topRight: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      bumperPaint,
    );
    canvas.drawLine(Offset(w - 22, 0), Offset(w - 22, h), bumperHighlight);

    // Hanging hole on the left
    canvas.drawOval(
      Rect.fromCenter(center: Offset(42, h / 2), width: 14, height: 26),
      Paint()..color = const Color(0xFF141416),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(42, h / 2), width: 14, height: 26),
      Paint()
        ..color = const Color(0xFF48484A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Hanging hole on the right
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w - 42, h / 2), width: 14, height: 26),
      Paint()..color = const Color(0xFF141416),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w - 42, h / 2), width: 14, height: 26),
      Paint()
        ..color = const Color(0xFF48484A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Brand imprint on yellow body
    final brandPainter = TextPainter(
      text: const TextSpan(
        text: 'PRO-LEVEL 400',
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF222222),
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    brandPainter.paint(canvas, Offset(w / 2 - brandPainter.width / 2, 10));

    // 4. Center Horizontal Acrylic Vial (Libela)
    final vialW = 140.0;
    final vialH = 34.0;
    final vialCenter = Offset(w / 2, h / 2 + 6);
    final vialRect = Rect.fromCenter(center: vialCenter, width: vialW, height: vialH);
    final vialRRect = RRect.fromRectAndRadius(vialRect, const Radius.circular(17));

    // Dark recessed cutout in the metal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: vialCenter, width: vialW + 8, height: vialH + 8),
        const Radius.circular(21),
      ),
      Paint()..color = const Color(0xFF18181A),
    );

    // Fluorescent Green Vial Fluid
    final fluidPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFB5FF42), // Bright neon chartreuse
          Color(0xFF86E81A), // Radioactive builder's green
          Color(0xFF67BC0C), // Fluid depth
        ],
      ).createShader(vialRect);
    canvas.drawRRect(vialRRect, fluidPaint);

    // 5. Air Bubble inside the vial
    // Bubble position moves according to roll angle:
    // Scale: 1° roll = ~3.2 pixels shift
    // Clamped inside the vial limits
    final maxBubbleShift = (vialW / 2) - 22.0;
    final bubbleShift = (rollDeg * 3.2).clamp(-maxBubbleShift, maxBubbleShift);
    final bubbleCenter = Offset(vialCenter.dx + bubbleShift, vialCenter.dy);

    final bubbleW = 28.0;
    final bubbleH = 22.0;
    final bubbleRect = Rect.fromCenter(center: bubbleCenter, width: bubbleW, height: bubbleH);

    // Bubble shadow and lighter core
    canvas.drawOval(
      bubbleRect,
      Paint()..color = const Color(0xFFD6FF7A).withValues(alpha: 0.95),
    );
    canvas.drawOval(
      Rect.fromCenter(center: bubbleCenter.translate(0, -2), width: bubbleW - 8, height: bubbleH - 8),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    // Bubble dark meniscus ring
    canvas.drawOval(
      bubbleRect,
      Paint()
        ..color = const Color(0xFF4A840B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // 6. Two Iconic Black Measurement Lines on the Libela Tube
    final linePaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.0;

    const lineDistance = 18.0; // Distance of marks from center
    canvas.drawLine(
      Offset(vialCenter.dx - lineDistance, vialCenter.dy - vialH / 2 + 1),
      Offset(vialCenter.dx - lineDistance, vialCenter.dy + vialH / 2 - 1),
      linePaint,
    );
    canvas.drawLine(
      Offset(vialCenter.dx + lineDistance, vialCenter.dy - vialH / 2 + 1),
      Offset(vialCenter.dx + lineDistance, vialCenter.dy + vialH / 2 - 1),
      linePaint,
    );

    // 7. Glass Reflections on acrylic tube
    final glassShine = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(vialRect.left, vialRect.top, vialW, vialH / 2));

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(vialRect.left + 2, vialRect.top + 2, vialW - 4, vialH / 2 - 2),
        topLeft: const Radius.circular(15),
        topRight: const Radius.circular(15),
      ),
      glassShine,
    );

    // Acrylic outer border
    canvas.drawRRect(
      vialRRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _ConstructionLevelPainter oldDelegate) {
    return oldDelegate.rollDeg != rollDeg || oldDelegate.isStable != isStable;
  }
}
