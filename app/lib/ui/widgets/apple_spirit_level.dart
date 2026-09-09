import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Iconic Apple Measure / Spirit Level ("Vodováha") widget.
/// 
/// Computes high-precision roll tilt angle when smartphone is placed flat
/// on the motorcycle fuel tank cap. Features fluid-damped bubble animation,
/// tabular numerical display, and automatic stability locking with haptic feedback.
class AppleSpiritLevelWidget extends StatefulWidget {
  final ValueChanged<double>? onAngleChanged;
  final ValueChanged<bool>? onStabilityChanged;
  final double? simulatedRollDeg; // For emulator / unit testing

  const AppleSpiritLevelWidget({
    super.key,
    this.onAngleChanged,
    this.onStabilityChanged,
    this.simulatedRollDeg,
  });

  @override
  State<AppleSpiritLevelWidget> createState() => AppleSpiritLevelWidgetState();
}

class AppleSpiritLevelWidgetState extends State<AppleSpiritLevelWidget>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _currentRollDeg = 0.0;
  double _currentPitchDeg = 0.0;
  double _filteredRollDeg = 0.0;
  double _filteredPitchDeg = 0.0;

  bool _isStable = false;
  final List<double> _recentRolls = [];
  Timer? _stabilityTimer;
  Timer? _simTimer;

  // Smoothing factor for fluid motion
  static const double _filterK = 0.25;

  double get currentRollDeg => _filteredRollDeg;
  bool get isStable => _isStable;

  @override
  void initState() {
    super.initState();
    _startSensorListener();
  }

  void _startSensorListener() {
    // If running in test or emulator mode with a pre-set simulated angle
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
        onError: (err) {
          _fallbackSimulation();
        },
      );
    } catch (_) {
      _fallbackSimulation();
    }
  }

  void _fallbackSimulation() {
    // Graceful fallback for Windows desktop / emulator without hardware gyro
    _simTimer?.cancel();
    double baseAngle = -12.4; // Typical motorcycle side stand lean
    int tick = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      tick++;
      // Subtle natural damping micro-variation that settles into stability
      final noise = tick > 30 ? 0.0 : sin(tick * 0.4) * 0.3;
      _updateAngle(baseAngle + noise, 0.5);
    });
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    // Phone placed flat on tank cap with screen facing upward:
    // ax: lateral tilt (roll, left/right)
    // ay: longitudinal tilt (pitch, forward/backward)
    // az: vertical gravity component (points down/through back of phone)

    final ax = event.x;
    final ay = event.y;
    final az = event.z;

    // Roll angle in degrees: negative for left tilt, positive for right tilt
    // In standard phone coordinate frame, when left edge is lowered, ax is positive.
    // We invert so that left lean = negative roll (matching motorcycle telemetry).
    final roll = -atan2(ax, sqrt(ay * ay + az * az)) * (180.0 / pi);
    final pitch = atan2(ay, az) * (180.0 / pi);

    _updateAngle(roll, pitch);
  }

  void _updateAngle(double roll, double pitch) {
    if (!mounted) return;

    setState(() {
      _currentRollDeg = roll;
      _currentPitchDeg = pitch;

      // Low-pass complementary filter for fluid damping
      _filteredRollDeg = _filteredRollDeg * (1.0 - _filterK) + _currentRollDeg * _filterK;
      _filteredPitchDeg = _filteredPitchDeg * (1.0 - _filterK) + _currentPitchDeg * _filterK;

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

      final newlyStable = delta < 0.25; // Less than 0.25° jitter over 1 second
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
    _stabilityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _isStable
        ? CupertinoColors.activeGreen
        : const Color(0xFF0A84FF);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Spirit Level Circular Dial
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF141416),
            border: Border.all(
              color: _isStable
                  ? CupertinoColors.activeGreen.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.12),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _isStable
                    ? CupertinoColors.activeGreen.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Concentric circles & crosshairs painter
                CustomPaint(
                  size: const Size(220, 220),
                  painter: _SpiritLevelDialPainter(
                    isStable: _isStable,
                    rollDeg: _filteredRollDeg,
                    pitchDeg: _filteredPitchDeg,
                  ),
                ),

                // Large Numerical Readout with Tabular Figures
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_filteredRollDeg.abs().toStringAsFixed(1)}°',
                      style: TextStyle(
                        fontFamily: '.SF Pro Display',
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: _isStable
                            ? CupertinoColors.activeGreen
                            : Colors.white,
                        letterSpacing: -1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _filteredRollDeg < -0.3
                          ? 'VLEVO (STOJÁNEK)'
                          : _filteredRollDeg > 0.3
                              ? 'VPRAVO'
                              : 'VODOROVNĚ',
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: _isStable
                            ? CupertinoColors.activeGreen
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Stability indicator pill
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _isStable
                ? CupertinoColors.activeGreen.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
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
              Icon(
                _isStable ? Icons.check_circle_rounded : Icons.sensors_rounded,
                size: 15,
                color: activeColor,
              ),
              const SizedBox(width: 7),
              Text(
                _isStable
                    ? 'Stabilní poloha — připraveno'
                    : 'Vyčkejte na ustálení na nádrži...',
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _isStable ? CupertinoColors.activeGreen : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpiritLevelDialPainter extends CustomPainter {
  final bool isStable;
  final double rollDeg;
  final double pitchDeg;

  _SpiritLevelDialPainter({
    required this.isStable,
    required this.rollDeg,
    required this.pitchDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Concentric inner rings (5°, 10°, 15° markings)
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.35, ringPaint);
    canvas.drawCircle(center, radius * 0.65, ringPaint);
    canvas.drawCircle(center, radius * 0.90, ringPaint);

    // 2. Cardinal Crosshairs
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.2;

    // Horizontal left and right lines (leaving center open for text)
    canvas.drawLine(
      Offset(12, center.dy),
      Offset(center.dx - 54, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx + 54, center.dy),
      Offset(size.width - 12, center.dy),
      crossPaint,
    );

    // Vertical top and bottom lines
    canvas.drawLine(
      Offset(center.dx, 12),
      Offset(center.dx, center.dy - 36),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + 36),
      Offset(center.dx, size.height - 12),
      crossPaint,
    );

    // 3. Fluid Damped Apple Bubble
    // Scale bubble displacement: 1° tilt = ~4.5 pixels displacement
    // Maximum offset clamped within outer ring
    final maxBubbleOffset = radius - 30.0;
    final bubbleDx = (rollDeg * 4.5).clamp(-maxBubbleOffset, maxBubbleOffset);
    final bubbleDy = (pitchDeg * 4.5).clamp(-maxBubbleOffset, maxBubbleOffset);
    final bubbleCenter = center + Offset(bubbleDx, bubbleDy);

    final bubbleColor = isStable
        ? CupertinoColors.activeGreen
        : const Color(0xFF0A84FF);

    // Outer glow for bubble
    canvas.drawCircle(
      bubbleCenter,
      24,
      Paint()
        ..color = bubbleColor.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Bubble ring
    canvas.drawCircle(
      bubbleCenter,
      22,
      Paint()
        ..color = bubbleColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Bubble inner transluscent fill
    canvas.drawCircle(
      bubbleCenter,
      21,
      Paint()
        ..color = bubbleColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // Bubble center dot
    canvas.drawCircle(
      bubbleCenter,
      3.0,
      Paint()..color = bubbleColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SpiritLevelDialPainter oldDelegate) {
    return oldDelegate.isStable != isStable ||
        oldDelegate.rollDeg != rollDeg ||
        oldDelegate.pitchDeg != pitchDeg;
  }
}
