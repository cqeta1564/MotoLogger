import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/settings/esp_pairing_screen.dart';

/// In-memory fake implementation of DatabaseService for hermetic unit testing
class FakeDatabaseService extends DatabaseService {
  final Map<String, String> _settings = {};

  FakeDatabaseService() : super.forTesting();

  @override
  Future<void> saveSetting(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<String?> getSetting(String key) async {
    return _settings[key];
  }

  @override
  Future<void> removeSetting(String key) async {
    _settings.remove(key);
  }
}

void main() {
  group('DiscoveredBleDevice Tests', () {
    test('Calculates signal strength percentage properly across RSSI spectrum', () {
      const strong = DiscoveredBleDevice(id: '1', name: 'ESP-Strong', rssi: -40);
      const medium = DiscoveredBleDevice(id: '2', name: 'ESP-Medium', rssi: -70);
      const weak = DiscoveredBleDevice(id: '3', name: 'ESP-Weak', rssi: -100);
      const outOfBounds = DiscoveredBleDevice(id: '4', name: 'ESP-Far', rssi: -120);

      expect(strong.signalStrengthPercent, equals(100));
      expect(medium.signalStrengthPercent, equals(50));
      expect(weak.signalStrengthPercent, equals(0));
      expect(outOfBounds.signalStrengthPercent, equals(0));
    });

    test('Maps RSSI to discrete signal bars (1 to 4)', () {
      const bar4 = DiscoveredBleDevice(id: '1', name: 'ESP', rssi: -55);
      const bar3 = DiscoveredBleDevice(id: '2', name: 'ESP', rssi: -65);
      const bar2 = DiscoveredBleDevice(id: '3', name: 'ESP', rssi: -80);
      const bar1 = DiscoveredBleDevice(id: '4', name: 'ESP', rssi: -95);

      expect(bar4.signalBars, equals(4));
      expect(bar3.signalBars, equals(3));
      expect(bar2.signalBars, equals(2));
      expect(bar1.signalBars, equals(1));
    });
  });

  group('BleService Pairing & Discovery Lifecycle Tests', () {
    late BleService bleService;
    late FakeDatabaseService fakeDb;

    setUp(() {
      bleService = BleService();
      fakeDb = FakeDatabaseService();
    });

    tearDown(() {
      bleService.dispose();
    });

    test('Starts with no paired device', () {
      expect(bleService.isPaired, isFalse);
      expect(bleService.pairedDeviceId, isNull);
      expect(bleService.pairedDeviceName, isNull);
    });

    test('Initializes paired device from database if previously saved', () async {
      await fakeDb.saveSetting('paired_device_id', 'C4:DE:E2:81:4A:12');
      await fakeDb.saveSetting('paired_device_name', 'MotoLogger-ESP32 (Vpředu)');

      await bleService.initPairedDevice(dbService: fakeDb);

      expect(bleService.isPaired, isTrue);
      expect(bleService.pairedDeviceId, equals('C4:DE:E2:81:4A:12'));
      expect(bleService.pairedDeviceName, equals('MotoLogger-ESP32 (Vpředu)'));
    });

    test('Pairs with discovered device and persists to database', () async {
      bleService.enableMockMode(true);

      const targetDevice = DiscoveredBleDevice(
        id: 'E8:9F:6D:32:B1:09',
        name: 'MotoLogger-ESP32 #2',
        rssi: -62,
        isMotoLogger: true,
      );

      final success = await bleService.pairDevice(targetDevice, dbService: fakeDb);

      expect(success, isTrue);
      expect(bleService.isPaired, isTrue);
      expect(bleService.pairedDeviceId, equals('E8:9F:6D:32:B1:09'));
      expect(bleService.pairedDeviceName, equals('MotoLogger-ESP32 #2'));

      // Check database persistence
      final savedId = await fakeDb.getSetting('paired_device_id');
      final savedName = await fakeDb.getSetting('paired_device_name');
      expect(savedId, equals('E8:9F:6D:32:B1:09'));
      expect(savedName, equals('MotoLogger-ESP32 #2'));
    });

    test('Unpairs device and removes settings from database', () async {
      bleService.enableMockMode(true);

      const targetDevice = DiscoveredBleDevice(
        id: 'E8:9F:6D:32:B1:09',
        name: 'MotoLogger-ESP32 #2',
        rssi: -62,
        isMotoLogger: true,
      );

      await bleService.pairDevice(targetDevice, dbService: fakeDb);
      expect(bleService.isPaired, isTrue);

      await bleService.unpairDevice(dbService: fakeDb);

      expect(bleService.isPaired, isFalse);
      expect(bleService.pairedDeviceId, isNull);
      expect(bleService.pairedDeviceName, isNull);

      final savedId = await fakeDb.getSetting('paired_device_id');
      final savedName = await fakeDb.getSetting('paired_device_name');
      expect(savedId, isNull);
      expect(savedName, isNull);
    });

    test('Emits simulated devices during discovery in mock mode', () async {
      bleService.enableMockMode(true);

      final completer = Completer<List<DiscoveredBleDevice>>();
      final sub = bleService.discoveredDevicesStream.listen((devices) {
        if (devices.isNotEmpty && !completer.isCompleted) {
          completer.complete(devices);
        }
      });

      await bleService.startDiscoveryScan();
      final discovered = await completer.future.timeout(const Duration(seconds: 2));

      expect(discovered.isNotEmpty, isTrue);
      expect(discovered.first.isMotoLogger, isTrue);

      await bleService.stopDiscoveryScan();
      await sub.cancel();
    });
  });

  group('TelemetryManager Pairing Integration Tests', () {
    test('Exposes paired device status and delegates pairing operations', () async {
      final ble = BleService();
      ble.enableMockMode(true);
      final fakeDb = FakeDatabaseService();
      final gps = GpsService();

      final manager = TelemetryManager(
        bleService: ble,
        gpsService: gps,
        dbService: fakeDb,
      );

      // Allow async init tasks in constructor to settle
      await Future.delayed(Duration.zero);

      expect(manager.isPaired, isFalse);

      const device = DiscoveredBleDevice(
        id: 'AA:BB:CC:11:22:33',
        name: 'My-MotoLogger',
        rssi: -50,
      );

      final pairSuccess = await manager.pairDevice(device);
      expect(pairSuccess, isTrue);
      expect(manager.isPaired, isTrue);
      expect(manager.pairedDeviceId, equals('AA:BB:CC:11:22:33'));
      expect(manager.pairedDeviceName, equals('My-MotoLogger'));

      await manager.unpairDevice();
      expect(manager.isPaired, isFalse);
      expect(manager.pairedDeviceId, isNull);

      manager.dispose();
      ble.dispose();
    });
  });

  group('EspPairingScreen Widget Tests', () {
    testWidgets('Renders Apple-style pairing UI with radar and action buttons', (WidgetTester tester) async {
      final ble = BleService();
      ble.enableMockMode(true);
      final fakeDb = FakeDatabaseService();
      final gps = GpsService();

      final manager = TelemetryManager(
        bleService: ble,
        gpsService: gps,
        dbService: fakeDb,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EspPairingScreen(telemetryManager: manager),
        ),
      );

      // Initial frame
      await tester.pump();

      // Check header and titles
      expect(find.text('Párování jednotky'), findsOneWidget);
      expect(find.text('Jednotky v dosahu'), findsOneWidget);
      expect(find.text('Znovu vyhledat'), findsOneWidget);

      // Advance mock timer to allow mock BLE discovery to emit
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('DOSTUPNÉ JEDNOTKY'), findsOneWidget);

      // Cleanly unmount widget to trigger dispose on repeating animation controller
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      manager.dispose();
      ble.dispose();
    });
  });
}
