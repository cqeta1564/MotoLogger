import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';

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

              // SECTION 2: Sensor Calibration
              _buildSectionHeader('KALIBRACE NÁKLONU'),
              _buildInsetGroup([
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Před zahájením kalibrace postavte motocykl do přesně svislé polohy na rovném povrchu (např. na servisním stojanu).',
                        style: TextStyle(
                          color: AppTheme.appleMutedGray,
                          fontSize: 13,
                          height: 1.4,
                          letterSpacing: -0.2,
                          fontFamily: '-apple-system',
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () async {
                          await telemetryManager.tareZero();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                backgroundColor: const Color(0xFF1C1C1E),
                                content: const Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: AppTheme.appleGreen, size: 20),
                                    SizedBox(width: 10),
                                    Text(
                                      'Nulový náklon IMU byl úspěšně zkalibrován.',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.tune_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Vynulovat náklon (Tara)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontFamily: '-apple-system',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // SECTION 3: System Specifications
              _buildSectionHeader('SYSTÉMOVÉ PARAMETRY'),
              _buildInsetGroup([
                _buildSpecTile('Cílový hardware', 'MotoLogger (ESP32-S3)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Senzor IMU', 'CEVA / Hillcrest BNO085 9-DoF'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Fúze senzorů', 'Game Rotation Vector (100 Hz)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Frekvence BLE streamu', '25 Hz (28 bajtů / paket)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Přenosová rychlost CAN', '500 kbps (TWAI ovladač)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Záznam na SD kartu', 'Bezeztrátový DMA zápis (100 Hz)'),
                const Divider(color: Color(0xFFE5E5EA), height: 1, indent: 16, endIndent: 16),
                _buildSpecTile('Správa napájení', 'Automatické uspání po 15 s (0 mA)'),
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
