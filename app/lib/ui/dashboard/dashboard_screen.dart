import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/telemetry_manager.dart';
import '../../services/ble_service.dart';
import '../widgets/lean_gauge.dart';
import '../widgets/g_force_circle.dart';
import '../widgets/rpm_tachometer.dart';
import '../widgets/gear_indicator.dart';

class DashboardScreen extends StatelessWidget {
  final TelemetryManager telemetryManager;

  const DashboardScreen({super.key, required this.telemetryManager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: telemetryManager,
      builder: (context, _) {
        final pkt = telemetryManager.latestPacket;
        final isBleConnected = telemetryManager.bleService.state == BleConnectionState.connected;

        return Scaffold(
          appBar: AppBar(
            title: const Text('MOTOLOGGER TELEMETRY'),
            actions: [
              // Mock Demo Mode Toggle Button for instant testing
              IconButton(
                icon: const Icon(Icons.bolt),
                tooltip: 'Toggle Demo Simulation',
                color: isBleConnected ? AppTheme.primary : AppTheme.textMuted,
                onPressed: () {
                  final isMocking = telemetryManager.bleService.state == BleConnectionState.connected;
                  telemetryManager.bleService.enableMockMode(!isMocking);
                },
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Status Strip
                  _buildStatusStrip(pkt, isBleConnected),
                  const SizedBox(height: 12),

                  // RPM Tachometer Bar
                  RpmTachometer(currentRpm: pkt.engineRpm),
                  const SizedBox(height: 14),

                  // Gear and Speed Display
                  GearSpeedWidget(
                    gear: pkt.gear,
                    speedKmh: pkt.vehicleSpeedKmh,
                  ),
                  const SizedBox(height: 16),

                  // Central Lean Angle Arc Gauge
                  Center(
                    child: LeanGauge(
                      leanAngleDeg: pkt.leanAngleDeg,
                      maxLeftDeg: telemetryManager.maxLeanLeft,
                      maxRightDeg: telemetryManager.maxLeanRight,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Peak Stats Strip
                  _buildPeakStatsStrip(),
                  const SizedBox(height: 16),

                  // Lower Dynamics Grid: G-Force Circle + Pitch & Throttle
                  Row(
                    children: [
                      // G-G Friction Circle
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.surfaceLight),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'G - G FORCES',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GForceCircle(
                              accelX: pkt.accelXG,
                              accelY: pkt.accelYG,
                              size: 110,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Pitch & Throttle Cards
                      Expanded(
                        child: Column(
                          children: [
                            _buildMetricTile(
                              label: 'PITCH (DIVE / ACCEL)',
                              value: '${pkt.pitchDeg.toStringAsFixed(1)}°',
                              icon: Icons.swap_vert,
                              color: pkt.pitchDeg > 0 ? AppTheme.accent : AppTheme.primary,
                            ),
                            const SizedBox(height: 10),
                            _buildMetricTile(
                              label: 'THROTTLE POSITION',
                              value: '${pkt.throttlePosPct}%',
                              icon: Icons.speed,
                              color: AppTheme.success,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons: Tare Zero & Record Ride
                  _buildActionControls(context),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusStrip(dynamic pkt, bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // BLE Connection Badge
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? AppTheme.success : AppTheme.danger,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isConnected ? 'BLE CONNECTED' : 'BLE OFFLINE',
                style: TextStyle(
                  color: isConnected ? AppTheme.success : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          // Battery Voltage
          Row(
            children: [
              const Icon(Icons.bolt, size: 14, color: AppTheme.accent),
              const SizedBox(width: 4),
              Text(
                '${pkt.batteryVoltage.toStringAsFixed(1)}V',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Engine Temp
          Row(
            children: [
              const Icon(Icons.thermostat, size: 14, color: AppTheme.danger),
              const SizedBox(width: 4),
              Text(
                '${pkt.coolantTempC}°C',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeakStatsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('PEAK LEFT', '${telemetryManager.maxLeanLeft.abs().toStringAsFixed(1)}°', AppTheme.primary),
          Container(width: 1, height: 28, color: AppTheme.surfaceLight),
          _buildStatColumn('PEAK RIGHT', '${telemetryManager.maxLeanRight.abs().toStringAsFixed(1)}°', AppTheme.accent),
          Container(width: 1, height: 28, color: AppTheme.surfaceLight),
          _buildStatColumn('TOP SPEED', '${telemetryManager.topSpeed.toStringAsFixed(0)} km/h', AppTheme.textPrimary),
          Container(width: 1, height: 28, color: AppTheme.surfaceLight),
          _buildStatColumn('MAX G', '${telemetryManager.maxG.toStringAsFixed(2)}G', AppTheme.danger),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActionControls(BuildContext context) {
    final isRecording = telemetryManager.isRecording;

    return Row(
      children: [
        // Zero Tare Button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceLight,
              foregroundColor: AppTheme.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.tune, size: 20),
            label: const Text('TARE ZERO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () async {
              await telemetryManager.tareZero();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('IMU Zero-Tare Calibrated!'),
                    duration: Duration(seconds: 1),
                    backgroundColor: AppTheme.surfaceLight,
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        // Start / Stop Session Record Button
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? AppTheme.danger : AppTheme.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record, size: 20),
            label: Text(
              isRecording ? 'STOP LOGGING (${telemetryManager.sampleCount})' : 'START LOGGING',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
            ),
            onPressed: () async {
              if (isRecording) {
                await telemetryManager.stopRecording();
              } else {
                await telemetryManager.startRecording();
              }
            },
          ),
        ),
      ],
    );
  }
}
