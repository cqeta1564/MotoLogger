import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/apple_spirit_level.dart';
import '../widgets/motorcycle_tank_illustration.dart';

/// Full-screen Apple HIG calibration experience for zero-lean calibration
/// using the motorcycle resting on its side stand and the smartphone placed
/// flat on the fuel tank cap.
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
  double _phoneRollDeg = -12.4; // Default realistic side stand lean
  bool _isStable = false;
  bool _isCalibrating = false;
  bool _showSuccessBadge = false;

  double get _rawEspDeg => widget.telemetryManager.latestRawLeanDeg;
  double get _calculatedOffset => _rawEspDeg - _phoneRollDeg;

  Future<void> _handleCalibrate() async {
    if (_isCalibrating) return;

    setState(() {
      _isCalibrating = true;
    });

    HapticFeedback.mediumImpact();

    // Calibrate offset and send via BLE to ESP unit
    await widget.telemetryManager.calibrateFromTank(phoneRollDeg: _phoneRollDeg);

    if (!mounted) return;

    setState(() {
      _isCalibrating = false;
      _showSuccessBadge = true;
    });

    HapticFeedback.heavyImpact();

    // Auto-dismiss confirmation after 2.5s or allow user to close
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) {
        setState(() {
          _showSuccessBadge = false;
        });
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
              'Korekce byla resetována na továrních 0.0°',
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
        final currentSavedOffset = widget.telemetryManager.mountingRollOffsetDeg;

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
              'Kalibrace na stojánku',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Step Instructions Card
                  _buildInstructionsCard(),

                  const SizedBox(height: 18),

                  // Motorcycle & Smartphone Vector Illustration
                  MotorcycleTankIllustration(
                    leanAngleDeg: _phoneRollDeg,
                    isCalibrated: _showSuccessBadge || currentSavedOffset != 0.0,
                    isStable: _isStable,
                  ),

                  const SizedBox(height: 24),

                  // Apple Spirit Level ("Vodováha")
                  AppleSpiritLevelWidget(
                    onAngleChanged: (angle) {
                      setState(() {
                        _phoneRollDeg = angle;
                      });
                    },
                    onStabilityChanged: (stable) {
                      setState(() {
                        _isStable = stable;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // Real-time Calibration Comparison Matrix
                  _buildComparisonMatrix(currentSavedOffset),

                  const SizedBox(height: 24),

                  // Success Badge or Action Button
                  if (_showSuccessBadge)
                    _buildSuccessBanner()
                  else
                    _buildCalibrateButton(),

                  const SizedBox(height: 14),

                  // Factory Reset Option
                  Center(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      onPressed: _handleResetDefault,
                      child: const Text(
                        'Obnovit tovární nulování (0.0°)',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          color: Colors.white38,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: CupertinoColors.activeBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'POSTUP KALIBRACE',
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStepRow(1, 'Postavte motocykl na boční stojánek na rovný povrch.'),
          const SizedBox(height: 8),
          _buildStepRow(2, 'Položte telefon podélně na rovné víko nádrže.'),
          const SizedBox(height: 8),
          _buildStepRow(3, 'Počkejte, až se vodováha ustálí (zelená), a klepněte na tlačítko níže.'),
        ],
      ),
    );
  }

  Widget _buildStepRow(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13,
              color: Colors.white70,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonMatrix(double currentSavedOffset) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _buildMetricRow(
            label: 'Telefon na nádrži (naměřeno)',
            value: '${_phoneRollDeg.toStringAsFixed(1)}°',
            valueColor: _isStable ? CupertinoColors.activeGreen : Colors.white,
            icon: Icons.smartphone_rounded,
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),
          _buildMetricRow(
            label: 'Jednotka ESP (surový senzor)',
            value: '${_rawEspDeg.toStringAsFixed(1)}°',
            valueColor: CupertinoColors.systemCyan,
            icon: Icons.memory_rounded,
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),
          _buildMetricRow(
            label: 'Vypočtená korekce montáže',
            value: '${_calculatedOffset > 0 ? "+" : ""}${_calculatedOffset.toStringAsFixed(1)}°',
            valueColor: CupertinoColors.activeOrange,
            icon: Icons.tune_rounded,
            highlight: true,
          ),
          if (currentSavedOffset != 0.0) ...[
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),
            _buildMetricRow(
              label: 'Aktuálně uložená korekce',
              value: '${currentSavedOffset > 0 ? "+" : ""}${currentSavedOffset.toStringAsFixed(1)}°',
              valueColor: Colors.white60,
              icon: Icons.save_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required String label,
    required String value,
    required Color valueColor,
    required IconData icon,
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.white38),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                color: highlight ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildCalibrateButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isStable
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
        color: _isStable ? CupertinoColors.activeGreen : CupertinoColors.activeBlue,
        onPressed: _isCalibrating ? null : _handleCalibrate,
        child: _isCalibrating
            ? const CupertinoActivityIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isStable
                        ? 'SYNCHRONIZOVAT S JEDNOTKOU'
                        : 'ZKALIBROVAT NÁKLON',
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
            color: CupertinoColors.activeGreen.withValues(alpha: 0.2),
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
              'Úspěšně zkalibrováno a uloženo do jednotky!',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14,
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
