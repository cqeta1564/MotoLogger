import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/construction_spirit_level.dart';
import '../widgets/phone_placement_animation.dart';

/// Clean, unified Apple HIG calibration experience for riders.
/// Offers both:
/// 1. Smart side-stand calibration with phone placement animation and classic yellow builder's level.
/// 2. Fast upright calibration for riders holding the bike vertical or on a paddock stand.
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
  bool _isStable = false;
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
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Unified segmented selector between Side-Stand and Upright mode
                  _buildModeSelector(),

                  const SizedBox(height: 20),

                  // Mode-specific content
                  if (_selectedModeIndex == 0)
                    _buildStandModeContent()
                  else
                    _buildUprightModeContent(),

                  const SizedBox(height: 24),

                  // Action Button or Success Banner
                  if (_showSuccessBanner)
                    _buildSuccessBanner()
                  else
                    _buildActionButton(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
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
        PhonePlacementAnimation(isPlaced: _isStable),

        const SizedBox(height: 20),

        // Humorous builder's yellow spirit level
        ConstructionSpiritLevelWidget(
          onAngleChanged: (angle) => setState(() => _phoneRollDeg = angle),
          onStabilityChanged: (stable) => setState(() => _isStable = stable),
        ),
      ],
    );
  }

  Widget _buildUprightModeContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.balance_rounded,
              size: 38,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Svislé srovnání',
            style: TextStyle(
              fontFamily: '.SF Pro Display',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Podržte motocykl přesně svisle nebo jej postavte na rovný paddock stojan. Poté potvrďte tlačítkem.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13.5,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    final isStandMode = _selectedModeIndex == 0;
    final isReady = isStandMode ? _isStable : true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isReady ? 0.12 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 16),
        borderRadius: BorderRadius.circular(16),
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
                        : 'SROVNAT VE SVISLÉ POLOZE',
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
