import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/bike_upright_animation.dart';
import '../widgets/construction_spirit_level.dart';
import '../widgets/phone_placement_animation.dart';

/// Clean, unified Apple HIG calibration experience for riders.
/// Offers both:
/// 1. Smart side-stand calibration with phone placement animation and classic yellow builder's level.
/// 2. Fast upright calibration with bike balance animation and classic yellow builder's level.
class TankCalibrationScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;

  const TankCalibrationScreen({
    super.key,
    required this.telemetryManager,
  });

  @override
  State<TankCalibrationScreen> createState() => _TankCalibrationScreenState();
}

class _TankCalibrationScreenState extends State<TankCalibrationScreen> {
  int _selectedModeIndex = 0; // 0: Na bočním stojánku, 1: Svisle na stojanu
  double _phoneRollDeg = -12.4;
  bool _isStandStable = false;
  bool _isUprightStable = true;
  bool _isCalibrating = false;
  bool _showSuccessBanner = false;

  Future<void> _handleCalibrateStand() async {
    if (_isCalibrating) return;

    setState(() => _isCalibrating = true);
    HapticFeedback.mediumImpact();

    await widget.telemetryManager.calibrateFromTank(phoneRollDeg: _phoneRollDeg);

    if (!mounted) return;

    setState(() {
      _isCalibrating = false;
      _showSuccessBanner = true;
    });
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() => _showSuccessBanner = false);
      }
    });
  }

  Future<void> _handleCalibrateUpright() async {
    if (_isCalibrating) return;

    setState(() => _isCalibrating = true);
    HapticFeedback.mediumImpact();

    await widget.telemetryManager.tareZero();

    if (!mounted) return;

    setState(() {
      _isCalibrating = false;
      _showSuccessBanner = true;
    });
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() => _showSuccessBanner = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.telemetryManager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF2F2F7),
            elevation: 0,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.xmark_circle_fill, color: Color(0xFF8E8E93), size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Srovnání náklonu',
              style: TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                letterSpacing: -0.3,
              ),
            ),
            centerTitle: true,
          ),
          body: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;
              // Aligns button bottom to exact physical pixel height of Dashboard action buttons
              final bottomSpacing = isLandscape ? 64.0 : 102.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Unified segmented selector between Side-Stand and Upright mode
                            _buildModeSelector(),

                            const SizedBox(height: 20),

                            // Mode-specific content (perfectly symmetric structure)
                            if (_selectedModeIndex == 0)
                              _buildStandModeContent()
                            else
                              _buildUprightModeContent(),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Fixed Bottom Action Area (aligned to exact vertical level of Dashboard buttons)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isLandscape ? 80 : 20,
                      8,
                      isLandscape ? 80 : 20,
                      bottomSpacing,
                    ),
                    child: _showSuccessBanner
                        ? _buildSuccessBanner()
                        : _buildActionButton(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildModeSelector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _selectedModeIndex,
        backgroundColor: Colors.transparent,
        thumbColor: Colors.white,
        children: {
          0: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.black87),
                SizedBox(width: 6),
                Text(
                  'Na bočním stojánku',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          1: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.straighten_rounded, size: 16, color: Colors.black87),
                SizedBox(width: 6),
                Text(
                  'Rovně (svisle)',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        },
        onValueChanged: (val) {
          if (val != null) {
            setState(() => _selectedModeIndex = val);
            HapticFeedback.selectionClick();
          }
        },
      ),
    );
  }

  Widget _buildStandModeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Outline Animation of placing phone on fuel tank cap
        PhonePlacementAnimation(isPlaced: _isStandStable),

        const SizedBox(height: 20),

        // Humorous builder's yellow spirit level
        ConstructionSpiritLevelWidget(
          key: const ValueKey('stand_spirit_level'),
          onAngleChanged: (angle) => setState(() => _phoneRollDeg = angle),
          onStabilityChanged: (stable) => setState(() => _isStandStable = stable),
        ),
      ],
    );
  }

  Widget _buildUprightModeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Outline Animation of motorcycle tilting to vertical 0°
        BikeUprightAnimation(isUpright: _isUprightStable),

        const SizedBox(height: 20),

        // Humorous builder's yellow spirit level
        ConstructionSpiritLevelWidget(
          key: const ValueKey('upright_spirit_level'),
          onStabilityChanged: (stable) => setState(() => _isUprightStable = stable),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final isStandMode = _selectedModeIndex == 0;
    final isReady = isStandMode ? _isStandStable : _isUprightStable;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final buttonHeight = isLandscape
        ? AppTheme.primaryButtonHeightLandscape
        : AppTheme.primaryButtonHeight;

    return Container(
      width: double.infinity,
      height: buttonHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isReady ? 0.12 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        color: isReady ? const Color(0xFF1C1C1E) : const Color(0xFFAEAEC2),
        onPressed: _isCalibrating
            ? null
            : (isStandMode ? _handleCalibrateStand : _handleCalibrateUpright),
        child: _isCalibrating
            ? const CupertinoActivityIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isReady ? Icons.check_rounded : Icons.tune_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isStandMode
                        ? (isReady ? 'SROVNAT NULOVÝ BOD' : 'ČEKÁM NA USTÁLENÍ...')
                        : (isReady ? 'SROVNAT VE SVISLÉ POLOZE' : 'ČEKÁM NA USTÁLENÍ...'),
                    style: const TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final bannerHeight = isLandscape
        ? AppTheme.primaryButtonHeightLandscape
        : AppTheme.primaryButtonHeight;

    return Container(
      width: double.infinity,
      height: bannerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        border: Border.all(
          color: const Color(0xFF1C1C1E),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle_rounded, color: Color(0xFF1C1C1E), size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Srovnáno. Jednotka je připravená.',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
