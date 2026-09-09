import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/corner_gradient_breather.dart';
import '../widgets/gg_friction_reticle.dart';
import '../widgets/slide_to_unlock.dart';
import '../widgets/apple_tab_bar.dart';

/// The core motorcycle telemetry activity screen ("Jízda").
/// 
/// Strictly built to user directives:
/// - Light Apple design with pure white background (#FFFFFF).
/// - Dynamic corner color blends ("barevný přeliv") that breathe with lean angle.
/// - Bold black typography on white canvas for outdoor sunlight legibility.
/// - Naked G-G friction reticle directly on the canvas without any container box.
/// - Locked by default with Slide-to-Unlock.
/// - Screen automatically locks once the rider sets off and rides for a brief moment.
/// - When unlocked: Bottom nav bar + Pause button above it.
/// - When paused: Splits into Stop/Save (red) and Continue (green).
/// - Pre-ride Tare Zero calibration modal on session start.
class DashboardScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;
  final ValueChanged<int>? onNavigateTab;

  const DashboardScreen({
    super.key,
    required this.telemetryManager,
    this.onNavigateTab,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLocked = false;
  bool _wasStopped = true;
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    widget.telemetryManager.addListener(_onTelemetryUpdate);
  }

  @override
  void dispose() {
    widget.telemetryManager.removeListener(_onTelemetryUpdate);
    _autoLockTimer?.cancel();
    super.dispose();
  }

  void _onTelemetryUpdate() {
    final speed = widget.telemetryManager.latestPacket.vehicleSpeedKmh;
    if (speed < 10.0) {
      _wasStopped = true;
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
    } else {
      // Speed >= 10 km/h
      if (!_isLocked && _wasStopped) {
        // The rider just set off from standstill ("rozjel se")!
        // Lock screen after riding for 2.5 seconds:
        _autoLockTimer ??= Timer(const Duration(milliseconds: 2500), () {
          if (mounted && !_isLocked) {
            HapticFeedback.lightImpact();
            // Automatically begin recording if not yet recording so no ride data is missed
            if (!widget.telemetryManager.isRecording) {
              widget.telemetryManager.startRecording();
            }
            setState(() {
              _isLocked = true;
              _wasStopped = false;
            });
          }
        });
      }
    }
  }

  void _onUnlocked() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    setState(() {
      _isLocked = false;
    });
    // If the rider unlocks while already in motion (>= 10 km/h), allow 7s grace period to interact
    final speed = widget.telemetryManager.latestPacket.vehicleSpeedKmh;
    if (speed >= 10.0) {
      _autoLockTimer = Timer(const Duration(seconds: 7), () {
        if (mounted && !_isLocked) {
          HapticFeedback.lightImpact();
          setState(() {
            _isLocked = true;
          });
        }
      });
    }
  }

  Future<void> _onStartRidePressed() async {
    HapticFeedback.heavyImpact();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    await widget.telemetryManager.startRecording();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Záznam jízdy byl zahájen!'),
          duration: Duration(milliseconds: 1500),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    }
  }

  void _onPausePressed() {
    HapticFeedback.mediumImpact();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    widget.telemetryManager.pauseRecording();
  }

  void _onContinuePressed() {
    HapticFeedback.mediumImpact();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    widget.telemetryManager.resumeRecording();
    setState(() {
      _isLocked = true; // Auto re-lock when ride resumes
    });
  }

  Future<void> _onStopAndSavePressed() async {
    HapticFeedback.heavyImpact();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    await widget.telemetryManager.stopRecording();
    setState(() {
      _isLocked = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jízda byla úspěšně uložena do historie!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  void _toggleDemoSimulation() {
    HapticFeedback.selectionClick();
    final isMocking = widget.telemetryManager.bleService.isMockMode;
    widget.telemetryManager.bleService.enableMockMode(!isMocking);
    if (isMocking) {
      widget.telemetryManager.resetPeaks();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!isMocking ? 'Demo simulace aktivována' : 'Demo simulace vypnuta'),
        duration: const Duration(milliseconds: 1200),
        backgroundColor: Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.telemetryManager,
      builder: (context, _) {
        final pkt = widget.telemetryManager.latestPacket;

        // Lean calculations: negative is left, positive is right
        final currentLean = pkt.leanAngleDeg;
        final leftLean = currentLean < 0 ? -currentLean : 0.0;
        final rightLean = currentLean > 0 ? currentLean : 0.0;
        final maxLeftLean = widget.telemetryManager.maxLeanLeft.abs();
        final maxRightLean = widget.telemetryManager.maxLeanRight.abs();

        return Scaffold(
          backgroundColor: Colors.white,
          body: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;

              return Stack(
                children: [
                  // 1. Dynamic Breathing Corner Color Blends ("Barevný přeliv podle náklonu")
                  Positioned.fill(
                    child: CornerGradientBreather(
                      leanAngleDeg: currentLean,
                      maxLeanLeftDeg: widget.telemetryManager.maxLeanLeft,
                      maxLeanRightDeg: widget.telemetryManager.maxLeanRight,
                    ),
                  ),

                  // 2. Main Content
                  Positioned.fill(
                    child: SafeArea(
                      child: isLandscape
                          ? _buildLandscapeLayout(pkt, leftLean, rightLean, maxLeftLean, maxRightLean)
                          : _buildPortraitLayout(pkt, leftLean, rightLean, maxLeftLean, maxRightLean),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ================= PORTRAIT LAYOUT =================
  Widget _buildPortraitLayout(
    dynamic pkt,
    double leftLean,
    double rightLean,
    double maxLeftLean,
    double maxRightLean,
  ) {
    return Column(
      children: [
        const SizedBox(height: 18),

        // Top Row: Apple Precision Lean Badges (Left & Right) with Peak Hold
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLeanBadge(leftLean.round(), maxLeftLean.round(), isLeft: true),
              _buildLeanBadge(rightLean.round(), maxRightLean.round(), isLeft: false),
            ],
          ),
        ),

        const Spacer(flex: 1),

        // Center: Speed Display (Apple Fitness / Maps Typography)
        GestureDetector(
          onTap: _toggleDemoSimulation,
          onLongPress: _toggleDemoSimulation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${pkt.vehicleSpeedKmh}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 114,
                  fontWeight: FontWeight.w800,
                  height: 0.82,
                  letterSpacing: -4.5,
                  fontFamily: '-apple-system',
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'KM/H',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  fontFamily: '-apple-system',
                ),
              ),
            ],
          ),
        ),

        const Spacer(flex: 1),

        // Naked G-G Friction Reticle (Apple Precision Instrument)
        GgFrictionReticle(
          accelXG: pkt.accelXG,
          accelYG: pkt.accelYG,
          frictionEnvelope: widget.telemetryManager.frictionEnvelopeRadii,
          size: 240,
        ),

        const Spacer(flex: 2),

        // Bottom Controls: Locked Slider OR Unlocked Navigation & Action Buttons
        _buildBottomControlsArea(isLandscape: false),
      ],
    );
  }

  // ================= LANDSCAPE LAYOUT =================
  Widget _buildLandscapeLayout(
    dynamic pkt,
    double leftLean,
    double rightLean,
    double maxLeftLean,
    double maxRightLean,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Top Left: Lean Badge Left
        Positioned(
          top: 14,
          left: 44,
          child: _buildLeanBadge(leftLean.round(), maxLeftLean.round(), isLeft: true),
        ),

        // Top Right: Lean Badge Right
        Positioned(
          top: 14,
          right: 44,
          child: _buildLeanBadge(rightLean.round(), maxRightLean.round(), isLeft: false),
        ),

        // Center Top: Speed Display
        Positioned(
          top: 10,
          child: GestureDetector(
            onTap: _toggleDemoSimulation,
            onLongPress: _toggleDemoSimulation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${pkt.vehicleSpeedKmh}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 78,
                    fontWeight: FontWeight.w800,
                    height: 0.85,
                    letterSpacing: -3.0,
                    fontFamily: '-apple-system',
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'KM/H',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    fontFamily: '-apple-system',
                  ),
                ),
              ],
            ),
          ),
        ),

        // Center: Naked G-G Friction Reticle
        Positioned(
          top: 105,
          child: GgFrictionReticle(
            accelXG: pkt.accelXG,
            accelYG: pkt.accelYG,
            frictionEnvelope: widget.telemetryManager.frictionEnvelopeRadii,
            size: 175,
          ),
        ),

        // Bottom Controls Area
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomControlsArea(isLandscape: true),
        ),
      ],
    );
  }

  // ================= COMMON COMPONENT BUILDERS =================

  Widget _buildLeanBadge(int angle, int maxAngle, {required bool isLeft}) {
    final isActive = angle > 0;
    final hasMax = maxAngle > 0;

    return Column(
      crossAxisAlignment: isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live Lean Angle
        Text(
          '$angle°',
          style: TextStyle(
            color: isActive ? Colors.black : const Color(0xFFC7C7CC),
            fontSize: 54,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: -2.0,
            height: 1.0,
            fontFamily: '-apple-system',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 5),

        // Apple Tactile Peak Chip ("MAX XX°")
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
          },
          onLongPress: () {
            HapticFeedback.heavyImpact();
            widget.telemetryManager.resetPeaks();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Maximální náklony byly vynulovány'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.black87,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasMax ? const Color(0xFFE5E5EA) : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'MAX ',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontFamily: '-apple-system',
                  ),
                ),
                Text(
                  '$maxAngle°',
                  style: TextStyle(
                    color: hasMax ? Colors.black : const Color(0xFFC7C7CC),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: '-apple-system',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControlsArea({required bool isLandscape}) {
    if (_isLocked) {
      // Locked State: Show Slide to Unlock Bar
      return Padding(
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 60 : 24,
          8,
          isLandscape ? 60 : 24,
          isLandscape ? 12 : 24,
        ),
        child: SlideToUnlock(
          onUnlocked: _onUnlocked,
          width: isLandscape ? 480 : double.infinity,
          height: isLandscape ? 58 : 64,
        ),
      );
    }

    // Unlocked State: Show Action Button(s) directly above Bottom Navigation Bar
    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Action Buttons depending on Recording State:
          // 1. Not recording -> [ ZAHÁJIT JÍZDU ]
          // 2. Recording & Paused -> [ UKONČIT & ULOŽIT ] and [ POKRAČOVAT ]
          // 3. Recording & Active -> [ POZASTAVIT JÍZDU ]
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isLandscape ? 80 : 20, vertical: 8),
            child: _buildRecordingActionButton(isLandscape),
          ),

          // Unified Apple Tab Bar
          AppleTabBar(
            currentIndex: 0,
            isLandscape: isLandscape,
            onTabSelected: (idx) {
              if (idx > 0) {
                widget.onNavigateTab?.call(idx);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingActionButton(bool isLandscape) {
    final isRecording = widget.telemetryManager.isRecording;
    final isPaused = widget.telemetryManager.isPaused;
    final buttonHeight = isLandscape
        ? AppTheme.primaryButtonHeightLandscape
        : AppTheme.primaryButtonHeight;

    if (!isRecording) {
      // 1. Not recording: prominent Apple Green Start button
      return SizedBox(
        width: isLandscape ? 460 : double.infinity,
        height: buttonHeight,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF34C759),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
            ),
            shadowColor: const Color(0x6034C759),
          ),
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
          label: const Text(
            'ZAHÁJIT JÍZDU',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.2,
              fontFamily: '-apple-system',
            ),
          ),
          onPressed: _onStartRidePressed,
        ),
      );
    }

    if (isPaused) {
      // 2. Paused: Stop & Save (Red) + Continue (Green) - exactly same unified height
      return SizedBox(
        width: isLandscape ? 460 : double.infinity,
        height: buttonHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stop & Save Button (Crimson Red)
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
                  ),
                  shadowColor: const Color(0x60FF3B30),
                ),
                icon: const Icon(Icons.stop_rounded, size: 22),
                label: const Text(
                  'UKONČIT & ULOŽIT',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                    fontFamily: '-apple-system',
                  ),
                ),
                onPressed: _onStopAndSavePressed,
              ),
            ),
            const SizedBox(width: 14),
            // Continue Button (Apple Green)
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34C759),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
                  ),
                  shadowColor: const Color(0x6034C759),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text(
                  'POKRAČOVAT',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                    fontFamily: '-apple-system',
                  ),
                ),
                onPressed: _onContinuePressed,
              ),
            ),
          ],
        ),
      );
    }

    // 3. Actively recording: Pause button (Apple Dark Slate with Orange pause icon)
    return SizedBox(
      width: isLandscape ? 460 : double.infinity,
      height: buttonHeight,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1C1C1E),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
          ),
        ),
        icon: const Icon(Icons.pause_rounded, color: Color(0xFFFF9500), size: 24),
        label: const Text(
          'POZASTAVIT JÍZDU',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.2,
            fontFamily: '-apple-system',
          ),
        ),
        onPressed: _onPausePressed,
      ),
    );
  }
}
