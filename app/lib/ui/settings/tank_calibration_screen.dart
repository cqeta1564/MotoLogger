import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';
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
  double _phoneRollDeg = 0.0;
  bool _isStandStable = false;
  bool _isUprightStable = false;
  bool _isCalibrating = false;
  bool _showSuccessBanner = false;

  Future<void> _calibrate() async {
    if (_isCalibrating) return;
    final manager = widget.telemetryManager;
    if (!manager.isSimulationMode &&
        manager.bleService.state != BleConnectionState.connected) {
      return;
    }
    setState(() => _isCalibrating = true);
    try {
      // A demo calibration never changes the real motorcycle's persisted offset.
      if (!manager.isSimulationMode) {
        if (_selectedModeIndex == 0) {
          await manager.calibrateFromTank(phoneRollDeg: _phoneRollDeg);
        } else {
          await manager.calibrateUpright();
        }
      }
      if (mounted) setState(() => _showSuccessBanner = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Kalibraci se nepodařilo odeslat. Zkontrolujte připojení a zkuste to znovu.')));
      }
    } finally {
      if (mounted) setState(() => _isCalibrating = false);
    }
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
            leading: const GlassBackButton(),
            title: const Text(
              'Srovnání náklonu',
              style: TextStyle(
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
              final bottomSpacing = 20.0 + MediaQuery.paddingOf(context).bottom;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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

  Widget _buildModeSelector() => CupertinoSlidingSegmentedControl<int>(
        groupValue: _selectedModeIndex,
        children: const {
          0: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Na stojánku', textAlign: TextAlign.center)),
          1: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Svisle', textAlign: TextAlign.center)),
        },
        onValueChanged: (value) {
          if (_isCalibrating) return;
          if (value != null) {
            setState(() {
              _selectedModeIndex = value;
              _showSuccessBanner = false;
            });
          }
        },
      );

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
          onStabilityChanged: (stable) =>
              setState(() => _isStandStable = stable),
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
          onStabilityChanged: (stable) =>
              setState(() => _isUprightStable = stable),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final manager = widget.telemetryManager;
    final available = manager.isSimulationMode ||
        manager.bleService.state == BleConnectionState.connected;
    final stable = _selectedModeIndex == 0 ? _isStandStable : _isUprightStable;
    return PrimaryAction(
      label: !available
          ? 'Připojte jednotku'
          : !stable
              ? 'Čekám na ustálení…'
              : manager.isSimulationMode
                  ? 'Vyzkoušet kalibraci'
                  : 'Srovnat náklon',
      icon: CupertinoIcons.checkmark,
      busy: _isCalibrating,
      onPressed: available && stable ? _calibrate : null,
    );
  }

  Widget _buildSuccessBanner() => ContentGroup(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(CupertinoIcons.checkmark_circle,
              color: AppTheme.appleGreen),
          const SizedBox(width: 12),
          Expanded(
              child: Text(
                  widget.telemetryManager.isSimulationMode
                      ? 'Demo kalibrace dokončena. Nastavení motorky se nezměnilo.'
                      : 'Kalibrace odeslána do jednotky.',
                  style: const TextStyle(fontSize: 17))),
        ]),
      );
}
