import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/motion/app_motion.dart';
import '../../services/ble_service.dart';
import '../../services/telemetry_manager.dart';
import '../settings/esp_pairing_screen.dart';
import '../widgets/glass_surface.dart';
import '../widgets/gg_friction_reticle.dart';
import '../widgets/slide_to_unlock.dart';
import '../widgets/corner_gradient_breather.dart';

/// Live ride instruments with a separate, bounded control layer.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen(
      {super.key,
      required this.telemetryManager,
      this.onNavigateTab,
      this.onLockChanged});
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

  void _onTelemetryUpdate() {
    final speed = manager.latestPacket.vehicleSpeedKmh;
    if (!_available || speed < 10) {
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
    if (manager.latestPacket.vehicleSpeedKmh >= 10 &&
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
                      child: MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height &&
                              MediaQuery.textScalerOf(context).scale(17) <= 22
                          ? _landscapeInstruments()
                          : SingleChildScrollView(
                              key: const PageStorageKey('ride-scroll'),
                              padding:
                                  EdgeInsets.fromLTRB(20, 4, 20, 240 + bottom),
                              child: Center(
                                  child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 680),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AppPageTitle('Jízda',
                                          subtitle: 'MOTOLOGGER',
                                          trailing: _isLocked
                                              ? null
                                              : GlassIconButton(
                                                  icon: CupertinoIcons.ellipsis,
                                                  label: 'Ovládání jízdy',
                                                  onPressed: _showMenu)),
                                      _status(),
                                      const SizedBox(height: 20),
                                      ContentGroup(
                                          padding: const EdgeInsets.fromLTRB(
                                              20, 20, 20, 16),
                                          child: Column(children: [
                                            Text(
                                                manager.isRecording
                                                    ? (manager.isPaused
                                                        ? 'ZÁZNAM POZASTAVEN'
                                                        : 'PROBÍHÁ ZÁZNAM')
                                                    : 'RYCHLOST',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    letterSpacing: 1.4,
                                                    fontWeight: FontWeight.w600,
                                                    color: manager
                                                                .isRecording &&
                                                            !manager.isPaused
                                                        ? AppTheme.appleBlue
                                                        : AppTheme.textMuted)),
                                            Semantics(
                                                label: hasData
                                                    ? 'Rychlost ${pkt.vehicleSpeedKmh} kilometrů za hodinu'
                                                    : 'Rychlost není dostupná',
                                                excludeSemantics: true,
                                                child: Text(
                                                    hasData
                                                        ? '${pkt.vehicleSpeedKmh}'
                                                        : '—',
                                                    style: TextStyle(
                                                        fontSize: MediaQuery.sizeOf(
                                                                        context)
                                                                    .height <
                                                                700
                                                            ? 76
                                                            : 88,
                                                        fontWeight: FontWeight.w600,
                                                        height: 1.2,
                                                        letterSpacing: -5,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures()
                                                        ]))),
                                            const Text('km/h',
                                                style: TextStyle(
                                                    fontSize: 17,
                                                    color: AppTheme.textMuted)),
                                            const SizedBox(height: 24),
                                            Row(
                                                children: List.generate(
                                                    28,
                                                    (index) => Expanded(
                                                        child: Container(
                                                            height: 5,
                                                            margin:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        1.5),
                                                            decoration: BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        2),
                                                                color: hasData &&
                                                                        index <
                                                                            (pkt.engineRpm /
                                                                                12000 *
                                                                                28)
                                                                    ? (index > 23
                                                                        ? AppTheme
                                                                            .danger
                                                                        : AppTheme
                                                                            .appleBlue)
                                                                    : AppTheme.surfaceBorder))))),
                                            const SizedBox(height: 16),
                                            Row(children: [
                                              Expanded(
                                                  child: _metric(
                                                      'Otáčky',
                                                      hasData
                                                          ? '${pkt.engineRpm}'
                                                          : '—',
                                                      unit: 'ot/min')),
                                              Container(
                                                  width: 1,
                                                  height: 34,
                                                  color:
                                                      AppTheme.surfaceBorder),
                                              Expanded(
                                                  child: _metric(
                                                      'Převod',
                                                      hasData
                                                          ? (pkt.gear == 0
                                                              ? 'N'
                                                              : '${pkt.gear}')
                                                          : '—')),
                                            ]),
                                          ])),
                                      const SizedBox(height: 20),
                                      LayoutBuilder(
                                          builder: (context, constraints) {
                                        final largeText =
                                            MediaQuery.textScalerOf(context)
                                                    .scale(17) >
                                                23;
                                        final reticle = Semantics(
                                            label:
                                                'Přetížení ${sqrt(pkt.accelXG * pkt.accelXG + pkt.accelYG * pkt.accelYG).toStringAsFixed(2)} G',
                                            child: RepaintBoundary(
                                                child: GgFrictionReticle(
                                                    accelXG: hasData
                                                        ? pkt.accelXG
                                                        : 0,
                                                    accelYG: hasData
                                                        ? pkt.accelYG
                                                        : 0,
                                                    frictionEnvelope: manager
                                                        .frictionEnvelopeRadii,
                                                    size: largeText
                                                        ? 150
                                                        : min(
                                                            160,
                                                            constraints
                                                                    .maxWidth *
                                                                .46))));
                                        final left = _lean(
                                            'Vlevo',
                                            hasData
                                                ? max(0, -pkt.leanAngleDeg)
                                                : null,
                                            manager.maxLeanLeft.abs(),
                                            CupertinoIcons.arrow_turn_up_left);
                                        final right = _lean(
                                            'Vpravo',
                                            hasData
                                                ? max(0, pkt.leanAngleDeg)
                                                : null,
                                            manager.maxLeanRight.abs(),
                                            CupertinoIcons.arrow_turn_up_right);
                                        if (largeText) {
                                          return Column(children: [
                                            Row(children: [
                                              Expanded(child: left),
                                              Expanded(child: right)
                                            ]),
                                            const SizedBox(height: 12),
                                            reticle
                                          ]);
                                        }
                                        return Row(children: [
                                          Expanded(child: left),
                                          reticle,
                                          Expanded(child: right)
                                        ]);
                                      }),
                                      const SizedBox(height: 16),
                                      const Divider(),
                                      const SizedBox(height: 16),
                                      Row(children: [
                                        Expanded(
                                            child: _metric(
                                                'Vzdálenost',
                                                manager.totalDistanceKm
                                                    .toStringAsFixed(1),
                                                unit: 'km')),
                                        Expanded(
                                            child: _metric(
                                                'Max. rychlost',
                                                manager.topSpeed
                                                    .toStringAsFixed(0),
                                                unit: 'km/h')),
                                      ]),
                                      const SizedBox(height: 16),
                                      Text(
                                          manager.isSimulationMode
                                              ? 'Demo · simulovaná telemetrie a trasa Brno'
                                              : manager.latestPosition == null
                                                  ? 'GPS zatím není dostupné. Trasa nemusí být zaznamenána.'
                                                  : 'GPS aktivní · záznam se ukládá do telefonu',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textMuted)),
                                    ]),
                              )),
                            ))),
              Positioned(
                  left: 20,
                  right: 20,
                  bottom: (_isLocked ? 12 : AppTheme.navigationInset(context)) +
                      bottom,
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: _animatedControls(context)))),
            ]),
          );
        },
      );

  Widget _landscapeInstruments() {
    final packet = manager.latestPacket;
    return SingleChildScrollView(
      key: const PageStorageKey('ride-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 200),
      child: Column(children: [
        Row(children: [
          const Text('Jízda',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 16),
          Expanded(
              child: Text(
                  manager.isSimulationMode
                      ? 'Demo · okruh Brno'
                      : _available
                          ? 'Jednotka připojena'
                          : 'Jednotka je odpojena',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted))),
          if (!_isLocked)
            GlassIconButton(
                icon: CupertinoIcons.ellipsis,
                label: 'Ovládání jízdy',
                onPressed: _showMenu),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: ContentGroup(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_available ? '${packet.vehicleSpeedKmh}' : '—',
                              style: const TextStyle(
                                  fontSize: 60,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -2)),
                          const SizedBox(width: 8),
                          const Text('km/h',
                              style: TextStyle(
                                  fontSize: 15, color: AppTheme.textMuted)),
                        ]),
                    const SizedBox(height: 12),
                    Text(
                        _available
                            ? '${packet.engineRpm} ot/min · Převod ${packet.gear == 0 ? 'N' : packet.gear}'
                            : 'Čekám na telemetrii',
                        style: const TextStyle(
                            fontSize: 15, color: AppTheme.textMuted)),
                  ]))),
          const SizedBox(width: 20),
          Expanded(
              child: Row(children: [
            Expanded(
                child: _lean(
                    'Vlevo',
                    _available ? max(0, -packet.leanAngleDeg) : null,
                    manager.maxLeanLeft.abs(),
                    CupertinoIcons.arrow_turn_up_left)),
            GgFrictionReticle(
                accelXG: _available ? packet.accelXG : 0,
                accelYG: _available ? packet.accelYG : 0,
                frictionEnvelope: manager.frictionEnvelopeRadii,
                size: 100),
            Expanded(
                child: _lean(
                    'Vpravo',
                    _available ? max(0, packet.leanAngleDeg) : null,
                    manager.maxLeanRight.abs(),
                    CupertinoIcons.arrow_turn_up_right)),
          ])),
        ]),
      ]),
    );
  }

  Widget _status() {
    final demo = manager.isSimulationMode;
    final connected = manager.bleService.state == BleConnectionState.connected;
    final error = manager.bleService.state == BleConnectionState.error;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                  : AppTheme.textMuted),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            demo
                ? 'Demo jízda'
                : connected
                    ? 'Jednotka připojena'
                    : 'Připojte svou motorku',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
            demo
                ? 'Simulovaná data · okruh Brno'
                : connected
                    ? (manager.pairedDeviceName ?? 'MotoLogger')
                    : error
                        ? 'Bluetooth není dostupné'
                        : 'Jednotka zatím není připojena',
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
      ])),
      if (!_isLocked && !demo && !connected)
        TextButton(onPressed: _pair, child: const Text('Připojit')),
    ]);
  }

  Widget _metric(String label, String value, {String? unit}) =>
      Column(children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text([value, if (unit != null) unit].join(' '),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]);

  Widget _lean(String label, double? value, double peak, IconData icon) =>
      Column(children: [
        Icon(icon, size: 20, color: AppTheme.textMuted),
        const SizedBox(height: 8),
        Text(value == null ? '—' : '${value.round()}°',
            style: const TextStyle(
                fontSize: 30, letterSpacing: -1, fontWeight: FontWeight.w600)),
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        Text('max ${peak.round()}°',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ]);

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
          child: Column(children: [
            const Text('Ovládání uzamčeno za jízdy',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            SlideToUnlock(onUnlocked: _unlock, label: 'Přejetím odemknout'),
            TextButton(
                onPressed: _unlock, child: const Text('Odemknout ovládání')),
          ]));
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
                    borderRadius: BorderRadius.circular(14)),
                child: Semantics(
                    liveRegion: true,
                    child: Text(_error ?? manager.recordingError!,
                        style: const TextStyle(
                            color: Color(0xFFB3261E), fontSize: 14)))),
          if (!manager.isRecording)
            PrimaryAction(
                label: _available ? 'Zahájit jízdu' : 'Vyzkoušet demo',
                icon: _available
                    ? CupertinoIcons.circle_filled
                    : CupertinoIcons.play_fill,
                busy: _busy,
                onPressed: _available
                    ? _startRide
                    : () => manager.setSimulationMode(true))
          else if (!manager.isPaused)
            PrimaryAction(
                label: 'Pozastavit jízdu',
                icon: CupertinoIcons.pause_fill,
                onPressed: _busy ? null : manager.pauseRecording)
          else
            GlassSurface(
                radius: 24,
                padding: const EdgeInsets.all(6),
                child: Row(children: [
                  Expanded(
                      child: TextButton(
                          onPressed: _busy ? null : manager.resumeRecording,
                          child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('Pokračovat')))),
                  const SizedBox(width: 4),
                  Expanded(
                      child: PrimaryAction(
                          label: 'Uložit jízdu',
                          icon: CupertinoIcons.checkmark,
                          busy: _busy,
                          onPressed: _saveRide)),
                ])),
        ]);
  }
}
