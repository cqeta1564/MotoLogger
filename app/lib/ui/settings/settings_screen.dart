import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../core/theme/app_theme.dart';
import '../../core/preferences/app_preferences.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';
import '../widgets/glass_surface.dart';
import 'tank_calibration_screen.dart';
import 'bike_learning_screen.dart';
import 'bike_profiles_screen.dart';
import 'esp_pairing_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.telemetryManager});
  final TelemetryManager telemetryManager;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  TelemetryManager get manager => widget.telemetryManager;

  void _open(Widget screen) => Navigator.of(context)
      .push(CupertinoPageRoute<void>(builder: (_) => screen));

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Změnu se nepodařilo uložit. Zkuste to znovu.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
                  title: Text(title),
                  content: Text(message),
                  actions: [
                    CupertinoDialogAction(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Zrušit')),
                    CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(action)),
                  ])) ??
      false;

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferencesScope.maybeOf(context);
    return ListenableBuilder(
        listenable: Listenable.merge([manager, manager.canProfileService]),
        builder: (context, _) {
          final ble = manager.bleService;
          final demo = manager.isSimulationMode;
          final connected = ble.state == BleConnectionState.connected && !demo;
          final available = connected || demo;
          return Scaffold(
              backgroundColor: AppTheme.surfaceSecondary,
              body: SafeArea(
                bottom: false,
                child: ListView(
                  key: const PageStorageKey('settings-scroll'),
                  padding: EdgeInsets.fromLTRB(
                      20, 4, 20, 120 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const AppPageTitle('Nastavení',
                        subtitle: 'VAŠE MOTORKA, VAŠE DATA'),
                    ContentGroup(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                        color: AppTheme.surfaceSecondary,
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    child: const Icon(
                                        CupertinoIcons
                                            .antenna_radiowaves_left_right,
                                        size: 27)),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          demo
                                              ? 'Demo jednotka'
                                              : manager.pairedDeviceName ??
                                                  'MotoLogger',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                          demo
                                              ? 'Simulovaná data'
                                              : connected
                                                  ? 'Připojeno přes Bluetooth'
                                                  : ble.state ==
                                                          BleConnectionState
                                                              .scanning
                                                      ? 'Hledání jednotky…'
                                                      : ble.state ==
                                                              BleConnectionState
                                                                  .error
                                                          ? 'Bluetooth není dostupné'
                                                          : manager.isPaired
                                                              ? 'Jednotka je odpojena'
                                                              : 'Zatím není spárováno',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.textMuted)),
                                    ])),
                              ]),
                              const SizedBox(height: 20),
                              if (!demo)
                                PrimaryAction(
                                    label: connected
                                        ? 'Odpojit jednotku'
                                        : 'Připojit jednotku',
                                    icon: CupertinoIcons.link,
                                    busy: _busy,
                                    onPressed: manager.isRecording
                                        ? null
                                        : () {
                                            if (connected) {
                                              _perform(
                                                  () async => ble.disconnect());
                                            } else {
                                              _open(EspPairingScreen(
                                                  telemetryManager: manager));
                                            }
                                          }),
                              if (manager.isRecording)
                                const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                        'Připojení můžete změnit po uložení jízdy.',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textMuted))),
                            ])),
                    _section('Motorka'),
                    ContentGroup(
                        child: Column(children: [
                      SettingsRow(
                          icon: CupertinoIcons.slider_horizontal_3,
                          title: 'Profily motocyklů',
                          subtitle:
                              manager.canProfileService.activeProfile.name,
                          onTap: () => _open(BikeProfilesScreen(
                              canProfileService: manager.canProfileService,
                              telemetryManager: manager))),
                      _divider(),
                      SettingsRow(
                          icon: CupertinoIcons.compass,
                          title: 'Kalibrace náklonu',
                          subtitle: available
                              ? 'Na stojánku nebo ve svislé poloze'
                              : 'Nejprve připojte jednotku',
                          onTap: available && !manager.isRecording
                              ? () => _open(TankCalibrationScreen(
                                  telemetryManager: manager))
                              : null),
                      _divider(),
                      SettingsRow(
                          icon: CupertinoIcons.waveform,
                          title: 'Naučit se motorku',
                          subtitle: 'Záznam signálů a import profilu',
                          onTap: () => _open(
                              BikeLearningScreen(telemetryManager: manager))),
                    ])),
                    _section('Zobrazení a ukázka'),
                    ContentGroup(
                        child: Column(children: [
                      SettingsRow(
                          icon: CupertinoIcons.layers,
                          title: 'Omezit průhlednost',
                          subtitle: 'Neprůhledné ovládání pro lepší čitelnost',
                          trailing: CupertinoSwitch(
                              value: preferences?.reduceTransparency ?? false,
                              onChanged:
                                  preferences == null || preferences.saving
                                      ? null
                                      : (value) => _perform(() => preferences
                                          .setReduceTransparency(value)))),
                      _divider(),
                      SettingsRow(
                          icon: CupertinoIcons.play_circle,
                          title: 'Demo jízda',
                          subtitle: manager.isRecording
                              ? 'Režim lze změnit po uložení jízdy'
                              : connected
                                  ? 'Nejprve odpojte skutečnou jednotku'
                                  : 'Simulovaná telemetrie okruhu Brno',
                          trailing: CupertinoSwitch(
                              value: demo,
                              onChanged: manager.isRecording || connected
                                  ? null
                                  : manager.setSimulationMode)),
                    ])),
                    _section('Stav a úložiště'),
                    ContentGroup(
                        child: Column(children: [
                      SettingsRow(
                          icon: CupertinoIcons.location,
                          title: 'Poloha',
                          subtitle: demo
                              ? 'Simulovaná trasa'
                              : manager.latestPosition == null
                                  ? 'Poloha zatím není dostupná'
                                  : 'GPS aktivní'),
                      _divider(),
                      const SettingsRow(
                          icon: CupertinoIcons.tray,
                          title: 'Jízdy v telefonu',
                          subtitle: 'Lokální úložiště · funguje bez internetu'),
                      _divider(),
                      const SettingsRow(
                          icon: CupertinoIcons.info,
                          title: 'MotoLogger',
                          subtitle: 'Verze 1.0.0'),
                    ])),
                    if (manager.isPaired ||
                        manager.mountingRollOffsetDeg != 0) ...[
                      _section('Správa jednotky'),
                      ContentGroup(
                          child: Column(children: [
                        if (available && manager.mountingRollOffsetDeg != 0)
                          SettingsRow(
                              icon: CupertinoIcons.arrow_counterclockwise,
                              title: 'Obnovit nulový náklon',
                              subtitle: 'Zruší uloženou korekci montáže',
                              navigates: false,
                              onTap: _busy || manager.isRecording
                                  ? null
                                  : () async {
                                      if (await _confirm(
                                              'Obnovit nulový náklon?',
                                              'Uložená korekce se nastaví na nulu.',
                                              'Obnovit') &&
                                          mounted) {
                                        await _perform(
                                            manager.resetMountingOffset);
                                      }
                                    }),
                        if (manager.isPaired)
                          SettingsRow(
                              icon: CupertinoIcons.link,
                              title: 'Zapomenout jednotku',
                              navigates: false,
                              destructive: true,
                              onTap: _busy || manager.isRecording
                                  ? null
                                  : () async {
                                      if (await _confirm(
                                              'Zapomenout jednotku?',
                                              'Automatické připojení k této jednotce se vypne.',
                                              'Zapomenout') &&
                                          mounted) {
                                        await _perform(manager.unpairDevice);
                                      }
                                    }),
                      ])),
                    ],
                  ],
                ),
              ));
        });
  }

  Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
      child: Semantics(
          header: true,
          child: Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted))));
  Widget _divider() => const Divider(indent: 60, endIndent: 16);
}

class SettingsRow extends StatelessWidget {
  const SettingsRow(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.onTap,
      this.trailing,
      this.navigates = true,
      this.destructive = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool navigates;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            child: Row(children: [
              Icon(icon,
                  size: 23,
                  color: destructive ? AppTheme.danger : AppTheme.textMuted),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: destructive
                                ? AppTheme.danger
                                : AppTheme.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: AppTheme.textMuted))
                    ],
                  ])),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!
              ] else if (onTap != null && navigates) ...[
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_right,
                    size: 15, color: AppTheme.textMuted)
              ],
            ]),
          ),
        ),
      );
}
