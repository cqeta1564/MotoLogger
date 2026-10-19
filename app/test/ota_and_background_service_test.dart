import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/core/constants/ble_constants.dart';
import 'package:motologger/models/can_profile.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/settings/firmware_update_screen.dart';

class _MockDbService extends DatabaseService {
  _MockDbService() : super.forTesting();
  final Map<String, String> settings = {};

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<BikeProfile>> getAllBikeProfiles() async => [];

  @override
  Future<List<RideSession>> getAllSessions() async => [];

  @override
  Future<int> startSession(String title) async => 1;

  @override
  Future<void> updateSession(RideSession session) async {}

  @override
  Future<void> insertSampleBatch(List<FusedSample> batch) async {}
}

void main() {
  group('BLE Constants & OTA Protocol Tests', () {
    test('verifies OTA command and response opcodes match firmware protocol', () {
      expect(BleConstants.cmdOtaSetMode, 0x50);
      expect(BleConstants.respOtaStatus, 0xD0);
    });

    test('BleService manages OTA lifecycle, mock toggling and disconnect reset', () async {
      final ble = BleService();

      expect(ble.isOtaModeActive, isFalse);
      expect(ble.otaStateCode, 0);
      expect(ble.otaIpAddress, '192.168.4.1');

      ble.enableMockMode(true);
      final activated = await ble.setOtaMode(true);
      expect(activated, isTrue);
      expect(ble.isOtaModeActive, isTrue);
      expect(ble.otaStateCode, 1);

      final deactivated = await ble.setOtaMode(false);
      expect(deactivated, isTrue);
      expect(ble.isOtaModeActive, isFalse);
      expect(ble.otaStateCode, 0);

      // Re-enable and test disconnect() cleanup
      await ble.setOtaMode(true);
      expect(ble.isOtaModeActive, isTrue);
      ble.disconnect();
      expect(ble.isOtaModeActive, isFalse);
      expect(ble.otaStateCode, 0);

      ble.dispose();
    });

    test('BleService parses live firmware respOtaStatus binary notification packets', () {
      final ble = BleService();

      // Simulate firmware packet: [0xD0 (RESP_OTA_STATUS), 2 (UPDATING), 192, 168, 4, 1]
      ble.handleCommandResponseForTest([0xD0, 2, 192, 168, 4, 1]);
      expect(ble.isOtaModeActive, isTrue);
      expect(ble.otaStateCode, 2);
      expect(ble.otaIpAddress, '192.168.4.1');

      // Simulate firmware packet: [0xD0 (RESP_OTA_STATUS), 3 (SUCCESS_REBOOTING), 192, 168, 4, 1]
      ble.handleCommandResponseForTest([0xD0, 3, 192, 168, 4, 1]);
      expect(ble.isOtaModeActive, isFalse);
      expect(ble.otaStateCode, 3);

      ble.dispose();
    });

    test('TelemetryManager automatically cancels OTA if vehicle movement (> 5 km/h) is detected', () async {
      final db = _MockDbService();
      final ble = BleService();
      ble.mockStationary = true;
      ble.enableMockMode(true);
      final gps = GpsService();
      final manager = TelemetryManager(
        dbService: db,
        bleService: ble,
        gpsService: gps,
      );

      final activated = await manager.setOtaMode(true);
      expect(activated, isTrue);
      expect(ble.isOtaModeActive, isTrue);

      // Simulate vehicle starting to move (> 5 km/h)
      ble.emitMockTelemetryPacket(
        TelemetryPacket.initial().copyWith(
          vehicleSpeedKmh: 15,
          statusFlags: 0x0B,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(ble.isOtaModeActive, isFalse);

      manager.dispose();
      ble.dispose();
    });
  });

  group('FirmwareUpdateScreen Widget Tests', () {
    testWidgets('renders initial OTA screen with start action and network instructions', (tester) async {
      final db = _MockDbService();
      final ble = BleService();
      ble.mockStationary = true;
      ble.enableMockMode(true);
      final gps = GpsService();
      final manager = TelemetryManager(
        dbService: db,
        bleService: ble,
        gpsService: gps,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareUpdateScreen(telemetryManager: manager),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aktualizace firmwaru'), findsOneWidget);
      expect(find.text('Bezdrátový flash (OTA)'), findsOneWidget);
      expect(find.text('Aktivovat Wi-Fi aktualizaci'), findsOneWidget);

      // Tap activate button
      await tester.tap(find.text('Aktivovat Wi-Fi aktualizaci'));
      await tester.pumpAndSettle();

      // Now OTA is active in mock mode
      expect(find.text('Wi-Fi AP aktivní'), findsOneWidget);
      expect(find.text('MotoLogger-OTA'), findsOneWidget);
      expect(find.text('motologger'), findsOneWidget);
      expect(find.text('http://192.168.4.1'), findsOneWidget);
      expect(find.text('Ukončit režim aktualizace'), findsOneWidget);

      // Tap deactivate button
      await tester.tap(find.text('Ukončit režim aktualizace'));
      await tester.pumpAndSettle();

      expect(find.text('Aktivovat Wi-Fi aktualizaci'), findsOneWidget);

      manager.dispose();
      ble.dispose();
    });
  });
}
