import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';
import 'tank_calibration_screen.dart';
import 'bike_learning_screen.dart';
import 'bike_profiles_screen.dart';

/// Settings, BLE device connection, and sensor calibration screen.
/// Follows authentic Apple iOS Inset Grouped Settings guidelines.
class SettingsScreen extends StatelessWidget {
  final TelemetryManager telemetryManager;

  const SettingsScreen({super.key, required this.telemetryManager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: telemetryManager,
      builder: (context, _) {
        final ble = telemetryManager.bleService;
        final isConnected = ble.state == BleConnectionState.connected;
        final isScanning = ble.state == BleConnectionState.scanning;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            title: const Text('Nastavení'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // SECTION 1: Hardware Connection
              _buildSectionHeader('PŘIPOJENÍ HARDWARE'),
              _buildInsetGroup([
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? AppTheme.appleGreen.withValues(alpha: 0.12)
                              : isScanning
                                  ? AppTheme.appleOrange.withValues(alpha: 0.12)
                                  : const Color(0xFFF2F2F7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bluetooth_rounded,
                          color: isConnected
                              ? AppTheme.appleGreen
                              : isScanning
                                  ? AppTheme.appleOrange
                                  : AppTheme.appleMutedGray,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              BleConstants.deviceName,
                              style: TextStyle(
                                color: AppTheme.appleBlack,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                fontFamily: '-apple-system',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: isConnected
                                        ? AppTheme.appleGreen
                                        : isScanning
                                            ? AppTheme.appleOrange
                                            : AppTheme.appleMutedGray,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isConnected
                                      ? 'Připojeno'
                                      : isScanning
                                          ? 'Vyhledávání...'
                                          : 'Odpojeno',
                                  style: TextStyle(
                                    color: isConnected
                                        ? AppTheme.appleGreen
                                        : isScanning
                                            ? AppTheme.appleOrange
                                            : AppTheme.appleMutedGray,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: '-apple-system',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        color: isConnected ? const Color(0xFFF2F2F7) : AppTheme.appleBlue,
                        borderRadius: BorderRadius.circular(20),
                        onPressed: () {
                          if (isConnected) {
                            ble.disconnect();
                          } else {
                            ble.startScanAndAutoConnect();
                          }
                        },
                        child: Text(
                          isConnected ? 'Odpojit' : 'Připojit',
                          style: TextStyle(
                            color: isConnected ? AppTheme.appleRed : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Režim simulace (Demo)',
                        style: TextStyle(
                          color: AppTheme.appleBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          fontFamily: '-apple-system',
                        ),
                      ),
                      CupertinoSwitch(
                        activeTrackColor: AppTheme.appleGreen,
                        value: ble.isMockMode,
                        onChanged: (val) {
                          ble.enableMockMode(val);
                        },
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // SECTION 2: Calibration
              _buildSectionHeader('KALIBRACE NÁKLONU'),
              _buildInsetGroup([
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        fullscreenDialog: true,
                        builder: (context) => TankCalibrationScreen(
                          telemetryManager: telemetryManager,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.appleBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.two_wheeler_rounded,
                            color: AppTheme.appleBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Srovnání nulového náklonu',
                                style: TextStyle(
                                  color: AppTheme.appleBlack,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                telemetryManager.mountingRollOffsetDeg != 0.0
                                    ? 'Zkalibrováno (uloženo v jednotce)'
                                    : 'Na bočním stojánku nebo ve svislé poloze',
                                style: TextStyle(
                                  color: telemetryManager.mountingRollOffsetDeg != 0.0
                                      ? AppTheme.appleGreen
                                      : AppTheme.appleMutedGray,
                                  fontSize: 12.5,
                                  fontWeight: telemetryManager.mountingRollOffsetDeg != 0.0
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: Color(0xFFC7C7CC),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    HapticFeedback.lightImpact();

                    final confirmed = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('Obnovit výchozí nulování?'),
                        content: const Text(
                          'Korekce montážního úhlu bude nastavena zpět na výchozí hodnotu (0.0°).',
                        ),
                        actions: [
                          CupertinoDialogAction(
                            isDefaultAction: true,
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Zrušit'),
                          ),
                          CupertinoDialogAction(
                            isDestructiveAction: true,
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Obnovit'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed != true) return;

                    HapticFeedback.mediumImpact();
                    await telemetryManager.resetMountingOffset();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: const Color(0xFF1C1C1E),
                        content: const Row(
                          children: [
                            Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Nulový náklon byl resetován na výchozí stav.',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: AppTheme.appleBlack,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Obnovit výchozí nulování',
                                style: TextStyle(
                                  color: AppTheme.appleBlack,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Resetuje korekci montážního úhlu na 0.0°',
                                style: TextStyle(
                                  color: AppTheme.appleMutedGray,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // SECTION 3: CAN Bus & Bike Profile
              _buildSectionHeader('CAN SBĚRNICE & PROFIL MOTORKY'),
              _buildInsetGroup([
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        fullscreenDialog: true,
                        builder: (context) => BikeLearningScreen(
                          telemetryManager: telemetryManager,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.appleBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: AppTheme.appleBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Naučit se motorku (AI Asistent)',
                                style: TextStyle(
                                  color: AppTheme.appleBlack,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Záznam jízdy, export pro AI a konfigurace',
                                style: TextStyle(
                                  color: AppTheme.appleMutedGray,
                                  fontSize: 12.5,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: Color(0xFFC7C7CC),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (context) => BikeProfilesScreen(
                          canProfileService: telemetryManager.canProfileService,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.applePurple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: AppTheme.applePurple,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profily motocyklů & CAN',
                                style: TextStyle(
                                  color: AppTheme.appleBlack,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Aktivní: ${telemetryManager.canProfileService.activeProfile.name}',
                                style: TextStyle(
                                  color: telemetryManager.canProfileService.isCustomProfileActive
                                      ? AppTheme.appleGreen
                                      : AppTheme.appleMutedGray,
                                  fontSize: 12.5,
                                  fontWeight: telemetryManager.canProfileService.isCustomProfileActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: Color(0xFFC7C7CC),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // SECTION 4: Device Status
              _buildSectionHeader('STAV ZAŘÍZENÍ'),
              _buildInsetGroup([
                _buildSpecTile('Stav telemetrie', isConnected ? 'Aktivní přenos' : 'Čeká na připojení'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Záznam jízdy', 'Automatický při rozjezdu'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Paměťová karta', 'Připravena k zápisu'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Úsporný režim', 'Automatické uspání po 15 s'),
              ]),

              const SizedBox(height: 24),

              // SECTION 4: About
              _buildSectionHeader('O APLIKACI'),
              _buildInsetGroup([
                _buildSpecTile('Verze aplikace', '1.0.0 (Apple Edition)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Šifrované úložiště', 'SQLite aktivní'),
              ]),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.appleMutedGray,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          fontFamily: '-apple-system',
        ),
      ),
    );
  }

  Widget _buildInsetGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildSpecTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 14,
              letterSpacing: -0.2,
              fontFamily: '-apple-system',
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: '-apple-system',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
