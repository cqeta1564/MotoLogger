import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/dtc_code.dart';
import '../../services/ble_service.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/glass_surface.dart';

/// Dedicated OBD-II Diagnostics Screen.
/// This is the ONLY mode in which the MotoLogger ESP32-S3 transmits frames
/// on the motorcycle's CAN bus (Mode 01 live PIDs, Mode 03/07 DTC scan, Mode 04 clear).
/// Upon leaving this screen or exceeding 5 km/h, the unit automatically returns
/// to passive Listen-Only mode.
class DiagnosticsScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;

  const DiagnosticsScreen({
    super.key,
    required this.telemetryManager,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  TelemetryManager get manager => widget.telemetryManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final connected =
          manager.bleService.state == BleConnectionState.connected ||
              manager.isSimulationMode;
      if (connected && !manager.isRecording) {
        final active = await manager.setDiagnosticMode(true);
        if (mounted && active) {
          await manager.scanDiagnosticTroubleCodes();
        }
      }
    });
  }

  @override
  void dispose() {
    // Safety interlock: always return ESP32-S3 to passive Listen-Only mode when leaving Diagnostics
    manager.setDiagnosticMode(false);
    super.dispose();
  }

  Future<void> _confirmAndClearDtc() async {
    final confirmed = await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Smazat paměť závad ECU?'),
            content: const Text(
              'Opravdu chcete odeslat příkaz OBD-II Mode 04 pro vymazání uložených chybových kódů a zhasnutí kontrolky motoru (MIL)?\n\nÚkon provádějte pouze u stojícího motocyklu se zapnutým zapalováním.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Zrušit'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Smazat závady'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    HapticFeedback.mediumImpact();
    await manager.clearDiagnosticTroubleCodes();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final ble = manager.bleService;
        final demo = manager.isSimulationMode;
        final connected = ble.state == BleConnectionState.connected && !demo;
        final available = connected || demo;
        final diagActive = manager.isDiagnosticModeActive && available;
        final pkt = manager.latestPacket;
        final dtcs = manager.diagnosticTroubleCodes;
        final statusMsg = manager.diagnosticStatusMessage;

        final String gearDisplay = !available
            ? '—'
            : (pkt.gear < 0 ? '—' : (pkt.gear == 0 ? 'N' : '${pkt.gear}'));

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              manager.setDiagnosticMode(false);
            }
          },
          child: Scaffold(
            backgroundColor: AppTheme.surfaceSecondary,
            appBar: AppBar(
              backgroundColor: AppTheme.surfaceSecondary,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
              leading: const GlassBackButton(),
              title: const Text(
                'Diagnostika motocyklu',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              centerTitle: true,
            ),
            body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // 1. CAN Bus Transmitter Status Card
                ContentGroup(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: diagActive
                                  ? const Color(0x1A0066CC)
                                  : AppTheme.surfaceSecondary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              diagActive
                                  ? CupertinoIcons.radiowaves_right
                                  : CupertinoIcons.shield_fill,
                              color: diagActive
                                  ? AppTheme.accent
                                  : AppTheme.textMuted,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  diagActive
                                      ? 'Aktivní diagnostika (Vysílání OBD-II)'
                                      : 'Pasivní režim (Pouze příjem)',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  diagActive
                                      ? 'Jediný režim, ve kterém jednotka vysílá dotazy na CAN sběrnici. Při opuštění obrazovky nebo rozjezdu (> 5 km/h) se vysílání automaticky vypne.'
                                      : 'Jednotka je v bezpečném pasivním režimu (Listen-Only) a na sběrnici CAN nevysílá žádná data.',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (available) ...[
                            const SizedBox(width: 8),
                            CupertinoSwitch(
                              value: diagActive,
                              onChanged: manager.isRecording
                                  ? null
                                  : (val) => manager.setDiagnosticMode(val),
                            ),
                          ],
                        ],
                      ),
                      if (statusMsg != null && statusMsg.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceSecondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusMsg,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 2. ECU Fault Memory (OBD-II Mode 03 / Mode 07 / Mode 04)
                _sectionHeader('PAMĚŤ ZÁVAD ECU (OBD-II DTC)'),
                ContentGroup(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!available)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Pro vyčtení paměti závad nejprve připojte jednotku MotoLogger nebo zapněte Demo režim v Nastavení.',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        )
                      else if (dtcs.isEmpty)
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0x1A1F9D55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                CupertinoIcons.checkmark_shield_fill,
                                color: AppTheme.success,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Paměť závad je čistá',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    manager.lastDtcScanTime != null
                                        ? 'Žádné uložené (Mode 03) ani čekající (Mode 07) chybové kódy.'
                                        : 'Klepněte na tlačítko níže pro vyčtení chybových kódů z ECU.',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < dtcs.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 24,
                                  thickness: 0.5,
                                  color: AppTheme.surfaceBorder,
                                ),
                              _buildDtcTile(dtcs[i]),
                            ],
                          ],
                        ),
                      const SizedBox(height: 20),
                      PrimaryAction(
                        label: 'Vyčíst paměť závad',
                        icon: CupertinoIcons.search,
                        busy: manager.isScanningDtc,
                        onPressed: (!available || manager.isRecording)
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                manager.scanDiagnosticTroubleCodes();
                              },
                      ),
                      if (available && dtcs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        PrimaryAction(
                          label: 'Smazat chybové kódy (ECU Reset)',
                          icon: CupertinoIcons.trash,
                          destructive: true,
                          busy: manager.isClearingDtc,
                          onPressed:
                              manager.isRecording ? null : _confirmAndClearDtc,
                        ),
                      ],
                    ],
                  ),
                ),

                // 3. Live OBD-II Mode 01 Powertrain PIDs
                _sectionHeader('ŽIVÉ HODNOTY MOTORU (OBD-II MODE 01)'),
                ContentGroup(
                  child: Column(
                    children: [
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.speedometer,
                        title: 'Otáčky motoru (PID 0x0C)',
                        value: available ? '${pkt.engineRpm} rpm' : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.gauge,
                        title: 'Rychlost motocyklu (PID 0x0D)',
                        value: available ? '${pkt.vehicleSpeedKmh} km/h' : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.slider_horizontal_below_rectangle,
                        title: 'Poloha škrticí klapky (PID 0x11)',
                        value: available ? '${pkt.throttlePosPct} %' : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.thermometer,
                        title: 'Chladicí kapalina (PID 0x05)',
                        value: available ? '${pkt.coolantTempC} °C' : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.gear_alt,
                        title: 'Zařazený stupeň',
                        value: gearDisplay,
                      ),
                    ],
                  ),
                ),

                // 4. ESP32-S3 Hardware & Sensor Health
                _sectionHeader('STAV JEDNOTKY MOTOLOGGER'),
                ContentGroup(
                  child: Column(
                    children: [
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.battery_charging,
                        title: 'Palubní síť a dobíjení',
                        value: available
                            ? '${pkt.batteryVoltage.toStringAsFixed(2)} V (${pkt.isEngineRunning ? 'Dobíjí' : 'Klidové'})'
                            : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.compass,
                        title: 'IMU BNO085 (100 Hz)',
                        value: available
                            ? (pkt.isImuCalibrated
                                ? '${pkt.leanAngleDeg.toStringAsFixed(1)}° náklon · ${pkt.pitchDeg.toStringAsFixed(1)}° sklon'
                                : 'Není připraven')
                            : '—',
                      ),
                      _divider(),
                      _buildDiagMetricRow(
                        icon: CupertinoIcons.doc_text,
                        title: 'MicroSD úložiště',
                        value: available
                            ? (pkt.isSdCardMounted
                                ? 'Připraveno (100 Hz CSV)'
                                : 'Karta nevložena')
                            : '—',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildDtcTile(DiagnosticTroubleCode dtc) {
    final badgeColor = dtc.isPending ? AppTheme.warning : AppTheme.danger;
    final badgeBg =
        dtc.isPending ? const Color(0x1FD97706) : const Color(0x1FDC2626);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                dtc.code,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              dtc.statusLabelCz,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
            Text(
              '· ${dtc.systemCategoryCz}',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          dtc.descriptionCz,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagMetricRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _divider() => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 68,
        color: AppTheme.surfaceBorder,
      );
}
