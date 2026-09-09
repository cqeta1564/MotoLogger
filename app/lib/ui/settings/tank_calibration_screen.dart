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

  Future<void> _handleResetDefault() async {
    HapticFeedback.lightImpact();
    await widget.telemetryManager.resetMountingOffset();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF1C1C1E),
        content: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: CupertinoColors.systemCyan, size: 20),
            SizedBox(width: 10),
            Text(
              'Nulový náklon byl resetován na tovární výchozí stav.',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.telemetryManager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0C0C0E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0C0C0E),
            elevation: 0,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white60, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Srovnání náklonu',
              style: TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
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

                  const SizedBox(height: 14),

                  // Factory reset option
                  Center(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      onPressed: _handleResetDefault,
                      child: const Text(
                        'Obnovit výchozí nulování',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          color: Colors.white38,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),

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
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(4),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _selectedModeIndex,
        backgroundColor: Colors.transparent,
        thumbColor: const Color(0xFF2C2C2E),
        children: {
          0: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Na bočním stojánku',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
                Icon(Icons.straighten_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Rovně (svisle)',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
        // 1. Outline Animation of placing phone on fuel tank cap
        PhonePlacementAnimation(isPlaced: _isStable),

        const SizedBox(height: 20),

        // 2. Humorous builder's yellow spirit level
        ConstructionSpiritLevelWidget(
          onAngleChanged: (angle) => setState(() => _phoneRollDeg = angle),
          onStabilityChanged: (stable) => setState(() => _isStable = stable),
        ),

        const SizedBox(height: 16),

        // Simple, clean rider guidance
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: const [
              Icon(CupertinoIcons.sparkles, color: CupertinoColors.activeBlue, size: 18),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Motorka stojí bezpečně na stojánku. Položte telefon na víko a aplikace sama dopočte rovnou polohu.',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUprightModeContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.balance_rounded,
              size: 38,
              color: CupertinoColors.activeBlue,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Svislé srovnání',
            style: TextStyle(
              fontFamily: '.SF Pro Display',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Podržte motocykl přesně svisle v rukách nebo jej postavte na rovný paddock / servisní stojan. Poté stiskněte tlačítko níže.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13.5,
              color: Colors.white70,
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
            color: isReady
                ? CupertinoColors.activeGreen.withValues(alpha: 0.35)
                : CupertinoColors.activeBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 16),
        borderRadius: BorderRadius.circular(16),
        color: isReady ? CupertinoColors.activeGreen : CupertinoColors.activeBlue,
        onPressed: _isCalibrating
            ? null
            : (isStandMode ? _handleCalibrateStand : _handleCalibrateUpright),
        child: _isCalibrating
            ? const CupertinoActivityIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isReady ? Icons.check_circle_rounded : Icons.tune_rounded,
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
        color: CupertinoColors.activeGreen.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoColors.activeGreen.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.activeGreen.withValues(alpha: 0.25),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle_rounded, color: CupertinoColors.activeGreen, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Srovnáno, je to v lajně! Jednotka je připravená.',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
