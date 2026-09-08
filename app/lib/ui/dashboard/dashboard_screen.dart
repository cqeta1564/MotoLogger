import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/corner_gradient_breather.dart';
import '../widgets/gg_friction_reticle.dart';
import '../widgets/slide_to_unlock.dart';

/// The core motorcycle telemetry activity screen ("Jízda").
/// 
/// Strictly built to user directives:
/// - Light Apple design with pure white background (#FFFFFF).
/// - Dynamic corner color blends ("barevný přeliv") that breathe with lean angle.
/// - Bold black typography on white canvas for outdoor sunlight legibility.
/// - Naked G-G friction reticle directly on the canvas without any container box.
/// - Locked by default with Slide-to-Unlock.
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
  bool _isLocked = true;
  bool _isPaused = false;
  bool _hasPromptedTareThisSession = false;

  @override
  void initState() {
    super.initState();
    // Prompt Tare Zero setup if not currently recording
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.telemetryManager.isRecording && !_hasPromptedTareThisSession) {
        _showPreRideCalibrationDialog();
      }
    });
  }

  void _showPreRideCalibrationDialog() {
    _hasPromptedTareThisSession = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.two_wheeler, color: Colors.black, size: 28),
              SizedBox(width: 10),
              Text(
                'PŘÍPRAVA NA JÍZDU',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Srovnejte motorku do svislé polohy a proveďte kalibraci nulového náklonu (Tare Zero).',
                style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2F2F7),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE5E5EA)),
                  ),
                ),
                icon: const Icon(Icons.tune, color: Colors.black),
                label: const Text(
                  'ZKALIBROVAT (TARE ZERO)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await widget.telemetryManager.tareZero();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Senzor byl úspěšně zkalibrován (Tare Zero)!'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('POZDĚJI', style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await widget.telemetryManager.startRecording();
                      setState(() {
                        _isLocked = true;
                        _isPaused = false;
                      });
                    },
                    child: const Text(
                      'START JÍZDY',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _onUnlocked() {
    setState(() {
      _isLocked = false;
    });
  }

  void _onLockAgain() {
    HapticFeedback.lightImpact();
    setState(() {
      _isLocked = true;
    });
  }

  void _onPausePressed() {
    HapticFeedback.mediumImpact();
    widget.telemetryManager.pauseRecording();
    setState(() {
      _isPaused = true;
    });
  }

  void _onContinuePressed() {
    HapticFeedback.mediumImpact();
    widget.telemetryManager.resumeRecording();
    setState(() {
      _isPaused = false;
      _isLocked = true; // Auto re-lock when ride resumes
    });
  }

  Future<void> _onStopAndSavePressed() async {
    HapticFeedback.heavyImpact();
    await widget.telemetryManager.stopRecording();
    setState(() {
      _isPaused = false;
      _isLocked = false;
      _hasPromptedTareThisSession = false;
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
    final isMocking = widget.telemetryManager.bleService.state.name == 'connected';
    widget.telemetryManager.bleService.enableMockMode(!isMocking);
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
                          ? _buildLandscapeLayout(pkt, leftLean, rightLean)
                          : _buildPortraitLayout(pkt, leftLean, rightLean),
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
  ) {
    return Column(
      children: [
        const SizedBox(height: 18),

        // Top Row: Apple Precision Lean Badges (Left & Right)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLeanBadge(leftLean.round(), isLeft: true),
              _buildLeanBadge(rightLean.round(), isLeft: false),
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
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Top Left: Lean Badge Left
        Positioned(
          top: 14,
          left: 44,
          child: _buildLeanBadge(leftLean.round(), isLeft: true),
        ),

        // Top Right: Lean Badge Right
        Positioned(
          top: 14,
          right: 44,
          child: _buildLeanBadge(rightLean.round(), isLeft: false),
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

  Widget _buildLeanBadge(int angle, {required bool isLeft}) {
    final isActive = angle > 0;
    return Text(
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
          // Action Buttons: Pause OR [Stop/Save + Continue]
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isLandscape ? 80 : 20, vertical: 8),
            child: _isPaused
                ? Row(
                    children: [
                      // Stop & Save Button (Crimson Red)
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3B30),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            shadowColor: const Color(0x60FF3B30),
                          ),
                          icon: const Icon(Icons.stop, size: 22),
                          label: const Text(
                            'UKONČIT & ULOŽIT',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            shadowColor: const Color(0x6034C759),
                          ),
                          icon: const Icon(Icons.play_arrow, size: 22),
                          label: const Text(
                            'POKRAČOVAT',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                          ),
                          onPressed: _onContinuePressed,
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: isLandscape ? 460 : double.infinity,
                    height: isLandscape ? 50 : 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C1E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.pause, color: Color(0xFFFF9500), size: 22),
                      label: const Text(
                        'POZASTAVIT JÍZDU',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
                      onPressed: _onPausePressed,
                    ),
                  ),
          ),

          // Bottom Navigation Bar
          Container(
            height: isLandscape ? 58 : 72,
            decoration: const BoxDecoration(
              color: Color(0xFFF2F2F7),
              border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 1.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Historie',
                  isActive: false,
                  onTap: () => widget.onNavigateTab?.call(1),
                ),
                _buildNavItem(
                  icon: Icons.two_wheeler_rounded,
                  label: 'Jízda',
                  isActive: true,
                  onTap: () {},
                ),
                _buildNavItem(
                  icon: Icons.settings_rounded,
                  label: 'Nastavení',
                  isActive: false,
                  onTap: () => widget.onNavigateTab?.call(2),
                ),
                _buildNavItem(
                  icon: Icons.lock_outline_rounded,
                  label: 'Zamknout',
                  isActive: false,
                  onTap: _onLockAgain,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final color = isActive ? Colors.black : const Color(0xFF8E8E93);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                fontFamily: '-apple-system',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
