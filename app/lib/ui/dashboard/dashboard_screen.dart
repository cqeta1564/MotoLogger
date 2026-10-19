import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/motion/app_motion.dart';
import '../../models/telemetry_packet.dart';
import '../../services/ble_service.dart';
import '../../services/telemetry_manager.dart';
import '../settings/esp_pairing_screen.dart';
import '../widgets/glass_surface.dart';
import '../widgets/slide_to_unlock.dart';
import '../widgets/corner_gradient_breather.dart';
import '../widgets/gg_friction_reticle.dart';

/// Live ride cockpit with simplified, rider-centric instruments and Apple aesthetic.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.telemetryManager,
    this.onNavigateTab,
    this.onLockChanged,
  });

  final TelemetryManager telemetryManager;
  final ValueChanged<int>? onNavigateTab;
  final ValueChanged<bool>? onLockChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLocked = false;
  bool _wasStopped = true;
  bool _busy = false;
  String? _error;
  Timer? _autoLockTimer;

  TelemetryManager get manager => widget.telemetryManager;
  bool get _available =>
      manager.isSimulationMode ||
      manager.bleService.state == BleConnectionState.connected;

  @override
  void initState() {
    super.initState();
    manager.addListener(_onTelemetryUpdate);
  }

  @override
  void dispose() {
    manager.removeListener(_onTelemetryUpdate);
    _autoLockTimer?.cancel();
    super.dispose();
  }

  void _setLocked(bool value) {
    if (!mounted || _isLocked == value) return;
    setState(() => _isLocked = value);
    widget.onLockChanged?.call(value);
  }

  int _effectiveSpeedKmh(TelemetryPacket pkt) {
    if (pkt.vehicleSpeedKmh > 0) return pkt.vehicleSpeedKmh;
    final gpsSpeedMs = manager.latestPosition?.speed ?? 0.0;
    return gpsSpeedMs > 0.5 ? (gpsSpeedMs * 3.6).round() : 0;
  }

  void _onTelemetryUpdate() {
    final speed = _effectiveSpeedKmh(manager.latestPacket);
    if (!_available || speed <= 5) {
      _wasStopped = true;
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
    } else if (!_isLocked &&
        _wasStopped &&
        !_busy &&
        !manager.isPaused &&
        !manager.isSimulationMode) {
      _autoLockTimer ??= Timer(const Duration(milliseconds: 2500), () async {
        _autoLockTimer = null;
        if (!mounted || _isLocked || _busy) return;
        if (!manager.isRecording) {
          _wasStopped = false;
          await _startRide();
        }
        if (mounted && manager.isRecording) {
          _wasStopped = false;
          _setLocked(true);
        }
      });
    }
  }

  void _unlock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _setLocked(false);
    if (_effectiveSpeedKmh(manager.latestPacket) > 5 &&
        !manager.isSimulationMode) {
      _autoLockTimer =
          Timer(const Duration(seconds: 7), () => _setLocked(true));
    }
  }

  Future<void> _runAction(
      Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRide() => _runAction(() async {
        if (!_available) return;
        final now = DateTime.now();
        final date =
            '${now.day}.${now.month}. ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
        await manager.startRecording(
            '${manager.isSimulationMode ? 'Demo · Brno' : 'Jízda'} · $date');
        if (mounted) HapticFeedback.selectionClick();
      }, 'Záznam se nepodařilo zahájit. Zkontrolujte volné místo a zkuste to znovu.');

  Future<void> _saveRide() => _runAction(() async {
        await manager.stopRecording();
        if (!mounted) return;
        _setLocked(false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          persist: false,
          content: const Text('Jízda je uložena v telefonu.'),
          action: SnackBarAction(
              label: 'Zobrazit',
              onPressed: () => widget.onNavigateTab?.call(1)),
        ));
      }, 'Jízdu se nepodařilo uložit. Záznam zůstává pozastavený. Zkuste uložit znovu.');

  void _pair() => Navigator.of(context).push(CupertinoPageRoute<void>(
      builder: (_) => EspPairingScreen(telemetryManager: manager)));

  void _showMenu() => showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
            title: const Text('Ovládání jízdy'),
            message: const Text('Demo používá simulovaná data okruhu Brno.'),
            actions: [
              if (!manager.isRecording &&
                  (manager.isSimulationMode ||
                      manager.bleService.state != BleConnectionState.connected))
                CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      manager.setSimulationMode(!manager.isSimulationMode);
                    },
                    child: Text(manager.isSimulationMode
                        ? 'Vypnout demo'
                        : 'Vyzkoušet demo')),
              CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _pair();
                  },
                  child: const Text('Připojit jednotku')),
              CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    manager.resetPeaks();
                  },
                  child: const Text('Vynulovat maxima')),
              if (manager.isRecording)
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    manager.markCustomFinishLineHere();
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cílová čára byla označena na aktuální pozici.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Označit cíl (Lap)')),
            ],
            cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Zrušit')),
          ));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final pkt = manager.latestPacket;
          final hasData = _available;
          final bottom = MediaQuery.paddingOf(context).bottom;
          final size = MediaQuery.sizeOf(context);
          final isCompact = size.height < 640;

          return Scaffold(
            backgroundColor: AppTheme.surfaceSecondary,
            body: Stack(children: [
              Positioned.fill(
                child: CornerGradientBreather(
                  leanAngleDeg: pkt.leanAngleDeg,
                  enabled: hasData,
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  bottom: false,
                  child: size.width > size.height &&
                          MediaQuery.textScalerOf(context).scale(17) <= 22
                      ? _landscapeInstruments()
                      : SingleChildScrollView(
                          key: const PageStorageKey('ride-scroll'),
                          physics: const NeverScrollableScrollPhysics(),
                          primary: false,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            (_isLocked
                                    ? 155
                                    : AppTheme.navigationInset(context) + 56) +
                                bottom,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _cockpitHeader(),
                                  SizedBox(height: isCompact ? 6 : 10),
                                  if (manager.activeCircuit != null || manager.isRecording) ...[
                                    _lapTimingHud(isCompact),
                                    SizedBox(height: isCompact ? 6 : 10),
                                  ],
                                  _speedSection(pkt, hasData, isCompact),
                                  SizedBox(height: isCompact ? 10 : 16),
                                  _leanAndGgSection(pkt, hasData, isCompact),
                                  SizedBox(height: isCompact ? 6 : 10),
                                  _gpsStatusFootnote(isCompact),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: (_isLocked ? 12 : AppTheme.navigationInset(context)) +
                    bottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _animatedControls(context),
                  ),
                ),
              ),
            ]),
          );
        },
      );

  Widget _cockpitHeader() {
    final demo = manager.isSimulationMode;
    final connected = manager.bleService.state == BleConnectionState.connected;
    final error = manager.bleService.state == BleConnectionState.error;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            demo
                ? CupertinoIcons.play_circle
                : connected
                    ? CupertinoIcons.link
                    : CupertinoIcons.antenna_radiowaves_left_right,
            size: 20,
            color: demo
                ? AppTheme.appleOrange
                : connected
                    ? AppTheme.appleBlue
                    : AppTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  demo
                      ? 'Demo jízda'
                      : connected
                          ? 'Jednotka připojena'
                          : 'Připojte svou motorku',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  demo
                      ? 'Simulovaná data · okruh Brno'
                      : connected
                          ? (manager.pairedDeviceName ?? 'MotoLogger')
                          : error
                              ? 'Bluetooth není dostupné'
                              : 'Jednotka zatím není připojena',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!_isLocked && !demo && !connected)
            TextButton(
              onPressed: _pair,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(48, 32),
              ),
              child: const Text('Připojit'),
            ),
          if (!_isLocked) ...[
            const SizedBox(width: 4),
            GlassIconButton(
              icon: CupertinoIcons.ellipsis,
              label: 'Ovládání jízdy',
              onPressed: _showMenu,
            ),
          ],
        ],
      ),
    );
  }

  /// Compact Apple HIG Lap Timing HUD
  Widget _lapTimingHud(bool isCompact) {
    final circuit = manager.activeCircuit;
    final elapsed = manager.currentLapElapsed ?? Duration.zero;
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60);
    final tenths = ((elapsed.inMilliseconds % 1000) / 100).floor();
    final timeStr =
        '${minutes > 0 ? '$minutes:' : ''}${seconds.toString().padLeft(2, '0')}.$tenths';
    final delta = manager.lastLapDeltaSeconds;
    final isFaster = delta != null && delta <= 0;

    return Semantics(
      label: 'Měření kola ${manager.currentLapNumber}, čas $timeStr',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isCompact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'KOLO ${manager.currentLapNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    circuit?.name ?? 'Měření na okruhu',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: isCompact ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (delta != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isFaster
                      ? const Color(0xFF34C759).withValues(alpha: 0.12)
                      : const Color(0xFFFF3B30).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFaster
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${isFaster ? '' : '+'}${delta.toStringAsFixed(2)}s',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isFaster
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (!_isLocked)
              IconButton(
                icon: const Icon(CupertinoIcons.flag, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Označit cíl (Lap)',
                onPressed: () {
                  manager.markCustomFinishLineHere();
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Cílová čára byla označena na aktuální pozici.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Speed & Gear section displayed directly on the screen canvas across full width.
  Widget _speedSection(TelemetryPacket pkt, bool hasData, bool isCompact) {
    final effectiveSpeed = _effectiveSpeedKmh(pkt);
    final speedText = hasData ? '$effectiveSpeed' : '—';
    final gear = pkt.gear;
    final rpm = pkt.engineRpm;
    final rpmRatio = (hasData ? (rpm / 12000.0) : 0.0).clamp(0.0, 1.0);
    final isRedline = rpm >= 9500;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Status header above speed
        Text(
          manager.isRecording
              ? (manager.isPaused ? 'ZÁZNAM POZASTAVEN' : 'PROBÍHÁ ZÁZNAM')
              : 'RYCHLOST',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: manager.isRecording && !manager.isPaused
                ? AppTheme.appleBlue
                : AppTheme.textMuted,
          ),
        ),
        SizedBox(height: isCompact ? 1 : 2),

        // Giant Speed + Gear Badge in a balanced row
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Semantics(
                label: hasData
                    ? 'Rychlost $effectiveSpeed kilometrů za hodinu'
                    : 'Rychlost není dostupná',
                excludeSemantics: true,
                child: Text(
                  speedText,
                  style: TextStyle(
                    fontSize: isCompact ? 72 : 88,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: -4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'km/h',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              // Distinct Gear Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 10 : 12,
                  vertical: isCompact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: hasData && gear == 0
                      ? const Color(0xFF34C759).withValues(alpha: 0.12)
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasData && gear == 0
                        ? const Color(0xFF34C759)
                        : const Color(0xFFD1D1D6),
                    width: 1,
                  ),
                ),
                child: Text(
                  !hasData || gear < 0
                      ? '—'
                      : gear == 0
                          ? 'N'
                          : '$gear',
                  style: TextStyle(
                    fontSize: isCompact ? 20 : 24,
                    fontWeight: FontWeight.w700,
                    color: !hasData || gear < 0
                        ? AppTheme.textPrimary
                        : gear == 0
                            ? const Color(0xFF34C759)
                            : AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isCompact ? 6 : 8),

        // Apple-style RPM ribbon
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: isCompact ? 4 : 5,
              color: const Color(0xFFE5E5EA),
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) => Container(
                  width: constraints.maxWidth * rpmRatio,
                  decoration: BoxDecoration(
                    color: isRedline ? AppTheme.danger : AppTheme.appleBlue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Full-width row combining Left Lean, Central G-G Reticle, and Right Lean.
  Widget _leanAndGgSection(
      TelemetryPacket pkt, bool hasData, bool isCompact) {
    final leftAngle = hasData ? max(0.0, -pkt.leanAngleDeg) : null;
    final rightAngle = hasData ? max(0.0, pkt.leanAngleDeg) : null;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final reticleSize = isCompact
        ? (screenWidth < 360 ? 115.0 : 135.0)
        : screenHeight >= 750
            ? 175.0
            : 145.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Lean Section
          Expanded(
            child: _leanSection(
              label: 'VLEVO',
              value: leftAngle,
              peak: manager.maxLeanLeft.abs(),
              icon: CupertinoIcons.arrow_turn_up_left,
              isCompact: isCompact,
            ),
          ),
          // Center G-G Friction Reticle
          Semantics(
            label: 'G-G diagram zrychlení a přetížení',
            child: GgFrictionReticle(
              accelXG: hasData ? pkt.accelYG : 0.0,
              accelYG: hasData ? pkt.accelXG : 0.0,
              frictionEnvelope: manager.frictionEnvelopeRadii,
              size: reticleSize,
            ),
          ),
          // Right Lean Section
          Expanded(
            child: _leanSection(
              label: 'VPRAVO',
              value: rightAngle,
              peak: manager.maxLeanRight.abs(),
              icon: CupertinoIcons.arrow_turn_up_right,
              isCompact: isCompact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leanSection({
    required String label,
    required double? value,
    required double peak,
    required IconData icon,
    bool isCompact = false,
  }) {
    final angle = value ?? 0;
    Color angleColor = AppTheme.textPrimary;
    if (value != null && angle > 1) {
      if (angle <= 15) {
        angleColor = const Color(0xFF34C759);
      } else if (angle <= 30) {
        angleColor = const Color(0xFFFF9500);
      } else {
        angleColor = AppTheme.danger;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isCompact ? 12 : 14, color: AppTheme.textMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 10 : 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: isCompact ? 2 : 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value == null ? '—' : '${value.round()}°',
            style: TextStyle(
              fontSize: isCompact ? 26 : 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              color: angleColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(height: isCompact ? 1 : 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'max ${peak.round()}°',
            style: TextStyle(
              fontSize: isCompact ? 11 : 12,
              color: AppTheme.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  /// Subtle GPS status line at the bottom.
  Widget _gpsStatusFootnote(bool isCompact) {
    final demo = manager.isSimulationMode;
    final hasGps = manager.latestPosition != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: demo
                  ? AppTheme.appleOrange
                  : hasGps
                      ? const Color(0xFF34C759)
                      : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              demo
                  ? 'Demo · okruh Brno'
                  : hasGps
                      ? 'GPS aktivní · záznam se ukládá do telefonu'
                      : 'GPS zatím není dostupné',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                color: AppTheme.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Ergonomic landscape view for handlebar mounts across full screen canvas.
  Widget _landscapeInstruments() {
    final pkt = manager.latestPacket;
    final hasData = _available;
    final speedText = hasData ? '${_effectiveSpeedKmh(pkt)}' : '—';
    final gear = pkt.gear;
    final rpm = pkt.engineRpm;
    final rpmRatio = (hasData ? (rpm / 12000.0) : 0.0).clamp(0.0, 1.0);
    final isRedline = rpm >= 9500;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final leftAngle = hasData ? max(0.0, -pkt.leanAngleDeg) : null;
    final rightAngle = hasData ? max(0.0, pkt.leanAngleDeg) : null;

    return SingleChildScrollView(
      key: const PageStorageKey('ride-scroll'),
      physics: const NeverScrollableScrollPhysics(),
      primary: false,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        (_isLocked ? 155 : AppTheme.navigationInset(context) + 56) + bottom,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Jízda',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  manager.isSimulationMode
                      ? 'Demo · okruh Brno'
                      : hasData
                          ? 'Jednotka připojena'
                          : 'Jednotka je odpojena',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!_isLocked)
                GlassIconButton(
                  icon: CupertinoIcons.ellipsis,
                  label: 'Ovládání jízdy',
                  onPressed: _showMenu,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Left: Speed, Gear & RPM
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            speedText,
                            style: const TextStyle(
                              fontSize: 58,
                              height: 1,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'km/h',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasData && gear == 0
                                  ? const Color(0xFF34C759).withValues(alpha: 0.15)
                                  : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: hasData && gear == 0
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFE5E5EA),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              !hasData || gear < 0
                                  ? '—'
                                  : gear == 0
                                      ? 'N'
                                      : '$gear',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: !hasData || gear < 0
                                    ? AppTheme.textPrimary
                                    : gear == 0
                                        ? const Color(0xFF34C759)
                                        : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: 5,
                        color: const Color(0xFFE5E5EA),
                        alignment: Alignment.centerLeft,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Container(
                            width: constraints.maxWidth * rpmRatio,
                            decoration: BoxDecoration(
                              color: isRedline
                                  ? AppTheme.danger
                                  : AppTheme.appleBlue,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasData
                          ? '$rpm ot/min · ${manager.totalDistanceKm.toStringAsFixed(1)} km'
                          : 'Čekám na telemetrii',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 2. Center: G-G Reticle
              Semantics(
                label: 'G-G diagram zrychlení a přetížení',
                child: GgFrictionReticle(
                  accelXG: hasData ? pkt.accelYG : 0.0,
                  accelYG: hasData ? pkt.accelXG : 0.0,
                  frictionEnvelope: manager.frictionEnvelopeRadii,
                  size: 140,
                ),
              ),
              const SizedBox(width: 12),
              // 3. Right: Lean angles
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Expanded(
                      child: _leanSection(
                        label: 'VLEVO',
                        value: leftAngle,
                        peak: manager.maxLeanLeft.abs(),
                        icon: CupertinoIcons.arrow_turn_up_left,
                        isCompact: true,
                      ),
                    ),
                    Expanded(
                      child: _leanSection(
                        label: 'VPRAVO',
                        value: rightAngle,
                        peak: manager.maxLeanRight.abs(),
                        icon: CupertinoIcons.arrow_turn_up_right,
                        isCompact: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _animatedControls(BuildContext context) {
    final duration = AppMotion.duration(context, 220);
    // Avoid zero-duration RenderAnimatedSize layout re-entry on Android.
    if (duration == Duration.zero) return _controls();
    return AnimatedSize(
      duration: duration,
      curve: AppMotion.curve,
      alignment: Alignment.bottomCenter,
      child: _controls(),
    );
  }

  Widget _controls() {
    if (_isLocked) {
      return GlassSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'Ovládání uzamčeno za jízdy',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            SlideToUnlock(onUnlocked: _unlock, label: 'Přejetím odemknout'),
            TextButton(
              onPressed: _unlock,
              child: const Text('Odemknout ovládání'),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null || manager.recordingError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECEB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error ?? manager.recordingError!,
                style: const TextStyle(
                  color: Color(0xFFB3261E),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        if (!manager.isRecording)
          PrimaryAction(
            label: _available ? 'Zahájit jízdu' : 'Vyzkoušet demo',
            icon: _available
                ? CupertinoIcons.circle_filled
                : CupertinoIcons.play_fill,
            busy: _busy,
            onPressed: _available
                ? _startRide
                : () => manager.setSimulationMode(true),
          )
        else if (!manager.isPaused)
          PrimaryAction(
            label: 'Pozastavit jízdu',
            icon: CupertinoIcons.pause_fill,
            onPressed: _busy ? null : manager.pauseRecording,
          )
        else
          GlassSurface(
            radius: 24,
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : manager.resumeRecording,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Pokračovat'),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: PrimaryAction(
                    label: 'Uložit jízdu',
                    icon: CupertinoIcons.checkmark,
                    busy: _busy,
                    onPressed: _saveRide,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

