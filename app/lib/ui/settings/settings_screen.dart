import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';

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

        return Scaffold(
          appBar: AppBar(
            title: const Text('SETTINGS & CALIBRATION'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Bluetooth Hardware Card
              _buildCard(
                title: 'MOTOLOGGER HARDWARE CONNECTION',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.bluetooth_connected,
                      color: isConnected ? AppTheme.success : AppTheme.danger,
                      size: 28,
                    ),
                    title: const Text(BleConstants.deviceName, style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Status: ${ble.state.name.toUpperCase()}'),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? AppTheme.danger : AppTheme.primary,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        if (isConnected) {
                          ble.disconnect();
                        } else {
                          ble.startScanAndAutoConnect();
                        }
                      },
                      child: Text(isConnected ? 'DISCONNECT' : 'CONNECT'),
                    ),
                  ),
                  const Divider(color: AppTheme.surfaceLight),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Demo Simulation Mode', style: TextStyle(color: AppTheme.textPrimary)),
                      Switch(
                        activeColor: AppTheme.primary,
                        value: isConnected,
                        onChanged: (val) {
                          ble.enableMockMode(val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sensor Calibration Card
              _buildCard(
                title: 'SENSOR CALIBRATION',
                children: [
                  const Text(
                    'Ensure the motorcycle is held vertical or on a flat level paddock stand before zeroing.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceLight,
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.tune),
                    label: const Text('CALIBRATE ZERO LEAN ANGLE (TARE)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await telemetryManager.tareZero();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('IMU Zero-Tare Calibrated Successfully!'),
                            backgroundColor: AppTheme.surfaceLight,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // System Specs Card
              _buildCard(
                title: 'SYSTEM SPECIFICATIONS',
                children: [
                  _buildSpecRow('Target Hardware', 'MotoLogger v3.4 (ESP32-S3)'),
                  _buildSpecRow('IMU Subsystem', 'CEVA / Hillcrest BNO085 9-DoF'),
                  _buildSpecRow('IMU Fusion Mode', 'Game Rotation Vector (100 Hz)'),
                  _buildSpecRow('BLE Stream Rate', '25 Hz (28-byte binary packet)'),
                  _buildSpecRow('CAN Bus Baudrate', '500 kbps (TWAI driver)'),
                  _buildSpecRow('SD Blackbox Logging', 'Lossless DMA Block Writes (100 Hz)'),
                  _buildSpecRow('Power Management', 'Auto-shutdown 15s (0 mA drain)'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard({required String title, required List<Widget> children}) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.surfaceLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
