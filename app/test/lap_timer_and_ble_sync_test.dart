import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/lap_timer_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/ui/history/session_detail_screen.dart';
import 'package:motologger/ui/settings/settings_screen.dart';

class MockLapDatabaseService extends DatabaseService {
  MockLapDatabaseService() : super.forTesting();
  final Map<String, String> _settings = {};

  @override
  Future<List<FusedSample>> getSamplesForSession(int sessionId) async {
    return [];
  }

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    _settings[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LapTimerService & LapSplit Unit Tests', () {
    late LapTimerService lapService;

    setUp(() {
      lapService = LapTimerService();
    });

    test('resolveCircuit matches Automotodrom Brno correctly', () {
      final samples = [
        FusedSample(
          sessionId: 1,
          timestampMs: 1000,
          recordedAt: DateTime.now(),
          leanAngleDeg: 12.0,
          pitchDeg: 0.0,
          accelXG: 0.1,
          accelYG: 0.2,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 8000,
          vehicleSpeedKmh: 160,
          throttlePosPct: 80,
          coolantTempC: 85,
          gear: 4,
          batteryVoltage: 14.2,
          latitude: 49.203900,
          longitude: 16.444300, // Near Brno S/F straight
          altitude: 380.0,
          gpsSpeedKmh: 160.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),
      ];

      final circuit = lapService.resolveCircuit(samples);
      expect(circuit, isNotNull);
      expect(circuit!.name, 'Automotodrom Brno');
    });

    test('detectCrossings and detectLaps detects 2 laps with millisecond interpolation', () {
      // Automotodrom Brno gate:
      // p1: 49.204050, 16.444250, p2: 49.203700, 16.444250.
      // S/F line is at longitude 16.444250.
      // Crossing from East (lon 16.444350) to West (lon 16.444150) across lat ~49.203875.
      final samples = <FusedSample>[
        // First crossing (Start of Lap 1) at t = 10,000 ms
        FusedSample(
          sessionId: 1,
          timestampMs: 9900,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.3,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 10000,
          vehicleSpeedKmh: 180,
          throttlePosPct: 100,
          coolantTempC: 85,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444350, // Before line
          altitude: 380.0,
          gpsSpeedKmh: 180.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),
        FusedSample(
          sessionId: 1,
          timestampMs: 10100,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.3,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 10500,
          vehicleSpeedKmh: 185,
          throttlePosPct: 100,
          coolantTempC: 85,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444150, // After line (crosses at 50% = 10,000 ms)
          altitude: 380.0,
          gpsSpeedKmh: 185.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),

        // Intermediate corner (Lap 1 peak lean)
        FusedSample(
          sessionId: 1,
          timestampMs: 50000,
          recordedAt: DateTime.now(),
          leanAngleDeg: 48.5,
          pitchDeg: -1.0,
          accelXG: -0.2,
          accelYG: 1.2,
          accelZG: 1.0,
          gyroXDps: 10.0,
          gyroYDps: 0.0,
          gyroZDps: 15.0,
          engineRpm: 8000,
          vehicleSpeedKmh: 110,
          throttlePosPct: 40,
          coolantTempC: 88,
          gear: 3,
          batteryVoltage: 14.2,
          latitude: 49.206000,
          longitude: 16.448000,
          altitude: 395.0,
          gpsSpeedKmh: 110.0,
          bearing: 45.0,
          gpsAccuracyMeters: 1.0,
        ),

        // Second crossing (End of Lap 1, Start of Lap 2) at t = 130,000 ms (Lap 1 duration = 120,000 ms = 2:00.000)
        FusedSample(
          sessionId: 1,
          timestampMs: 129900,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.4,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 11000,
          vehicleSpeedKmh: 190,
          throttlePosPct: 100,
          coolantTempC: 86,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444350,
          altitude: 380.0,
          gpsSpeedKmh: 190.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),
        FusedSample(
          sessionId: 1,
          timestampMs: 130100,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.4,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 11200,
          vehicleSpeedKmh: 195,
          throttlePosPct: 100,
          coolantTempC: 86,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444150,
          altitude: 380.0,
          gpsSpeedKmh: 195.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),

        // Intermediate corner (Lap 2 peak lean and higher top speed)
        FusedSample(
          sessionId: 1,
          timestampMs: 180000,
          recordedAt: DateTime.now(),
          leanAngleDeg: -51.2,
          pitchDeg: 0.5,
          accelXG: 0.5,
          accelYG: 1.35,
          accelZG: 1.0,
          gyroXDps: -12.0,
          gyroYDps: 2.0,
          gyroZDps: -18.0,
          engineRpm: 12000,
          vehicleSpeedKmh: 205,
          throttlePosPct: 100,
          coolantTempC: 89,
          gear: 6,
          batteryVoltage: 14.2,
          latitude: 49.207000,
          longitude: 16.449000,
          altitude: 400.0,
          gpsSpeedKmh: 205.0,
          bearing: 120.0,
          gpsAccuracyMeters: 1.0,
        ),

        // Third crossing (End of Lap 2) at t = 248,500 ms (Lap 2 duration = 118,500 ms = 1:58.500)
        FusedSample(
          sessionId: 1,
          timestampMs: 248400,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.4,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 11500,
          vehicleSpeedKmh: 198,
          throttlePosPct: 100,
          coolantTempC: 87,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444350,
          altitude: 380.0,
          gpsSpeedKmh: 198.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),
        FusedSample(
          sessionId: 1,
          timestampMs: 248600,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.4,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 11800,
          vehicleSpeedKmh: 202,
          throttlePosPct: 100,
          coolantTempC: 87,
          gear: 5,
          batteryVoltage: 14.2,
          latitude: 49.203875,
          longitude: 16.444150,
          altitude: 380.0,
          gpsSpeedKmh: 202.0,
          bearing: 268.0,
          gpsAccuracyMeters: 1.0,
        ),
      ];

      final laps = lapService.detectLaps(samples);
      expect(laps.length, 2);

      // Lap 1: 120,000 ms = 2:00.000
      final lap1 = laps[0];
      expect(lap1.lapNumber, 1);
      expect(lap1.lapTimeMs, 120000);
      expect(lap1.formattedLapTime, '2:00.000');
      expect(lap1.isBestLap, isFalse);
      expect(lap1.deltaMs, 1500); // +1.50 s slower than Lap 2
      expect(lap1.formattedDelta, '+1.50 s');
      expect(lap1.maxLeanRightDeg, closeTo(48.5, 0.1));

      // Lap 2: 118,500 ms = 1:58.500 (Best Lap)
      final lap2 = laps[1];
      expect(lap2.lapNumber, 2);
      expect(lap2.lapTimeMs, 118500);
      expect(lap2.formattedLapTime, '1:58.500');
      expect(lap2.isBestLap, isTrue);
      expect(lap2.deltaMs, 0);
      expect(lap2.formattedDelta, '—');
      expect(lap2.topSpeedKmh, closeTo(205.0, 0.1));
      expect(lap2.maxLeanLeftDeg, closeTo(-51.2, 0.1));
    });

    test('detectLaps returns empty list for standard A to B road trip', () {
      final samples = [
        FusedSample(
          sessionId: 1,
          timestampMs: 1000,
          recordedAt: DateTime.now(),
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.1,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 3000,
          vehicleSpeedKmh: 50,
          throttlePosPct: 20,
          coolantTempC: 80,
          gear: 3,
          batteryVoltage: 14.0,
          latitude: 50.0878, // Prague
          longitude: 14.4205,
          altitude: 200.0,
          gpsSpeedKmh: 50.0,
          bearing: 90.0,
          gpsAccuracyMeters: 2.0,
        ),
        FusedSample(
          sessionId: 1,
          timestampMs: 60000,
          recordedAt: DateTime.now(),
          leanAngleDeg: 5.0,
          pitchDeg: 0.0,
          accelXG: 0.1,
          accelYG: 0.1,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: 4000,
          vehicleSpeedKmh: 80,
          throttlePosPct: 30,
          coolantTempC: 82,
          gear: 4,
          batteryVoltage: 14.1,
          latitude: 50.0900,
          longitude: 14.4500,
          altitude: 220.0,
          gpsSpeedKmh: 80.0,
          bearing: 85.0,
          gpsAccuracyMeters: 2.0,
        ),
      ];

      final laps = lapService.detectLaps(samples);
      expect(laps, isEmpty);
    });
  });

  group('SessionDetailScreen Lap Timer UI Widget Tests', () {
    testWidgets('SessionDetailScreen renders lap timer card when laps exist', (tester) async {
      final session = RideSession(
        id: 99,
        title: 'Brno Circuit Test',
        startTime: DateTime(2026, 6, 15, 14, 0),
        endTime: DateTime(2026, 6, 15, 14, 25),
        maxLeanLeftDeg: -50.0,
        maxLeanRightDeg: 48.0,
        topSpeedKmh: 210.0,
        maxGForce: 1.35,
        totalDistanceKm: 15.4,
        sampleCount: 1200,
      );

      final fakeDb = _FakeLapDbService();

      await tester.pumpWidget(MaterialApp(
        home: SessionDetailScreen(session: session, dbService: fakeDb),
      ));

      await tester.pumpAndSettle();

      // Verify that the Lap Timer section is rendered
      expect(find.text('ČASY NA KOLO'), findsOneWidget);
      expect(find.text('2 dokončená kola'), findsOneWidget);
      expect(find.text('Kolo 1'), findsOneWidget);
      expect(find.text('Kolo 2'), findsOneWidget);
      expect(find.text('Nejlepší'), findsOneWidget);
    });

    testWidgets('SessionDetailScreen lap card survives 1.8x accessibility text scaling without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = RideSession(
        id: 99,
        title: 'Brno Circuit Test',
        startTime: DateTime(2026, 6, 15, 14, 0),
        endTime: DateTime(2026, 6, 15, 14, 25),
        maxLeanLeftDeg: -50.0,
        maxLeanRightDeg: 48.0,
        topSpeedKmh: 210.0,
        maxGForce: 1.35,
        totalDistanceKm: 15.4,
        sampleCount: 1200,
      );

      final fakeDb = _FakeLapDbService();

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: SessionDetailScreen(session: session, dbService: fakeDb),
      ));

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ČASY NA KOLO'), findsOneWidget);
    });

    testWidgets('SessionDetailScreen omits lap timer card when no laps detected (A-to-B ride)', (tester) async {
      final session = RideSession(
        id: 100,
        title: 'Scenic Country Road',
        startTime: DateTime(2026, 6, 15, 10, 0),
        endTime: DateTime(2026, 6, 15, 11, 0),
        maxLeanLeftDeg: -25.0,
        maxLeanRightDeg: 28.0,
        topSpeedKmh: 95.0,
        maxGForce: 0.8,
        totalDistanceKm: 45.0,
        sampleCount: 300,
      );

      final emptyDb = MockLapDatabaseService();

      await tester.pumpWidget(MaterialApp(
        home: SessionDetailScreen(session: session, dbService: emptyDb),
      ));

      await tester.pumpAndSettle();

      // Verify that no Lap Timer card is displayed for ordinary street rides
      expect(find.text('ČASY NA KOLO'), findsNothing);
    });
  });

  group('SettingsScreen Live Hardware Diagnostics Tests', () {
    testWidgets('SettingsScreen displays em-dash when disconnected or in demo mode', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ble = BleService();
      final gps = GpsService();
      final db = MockLapDatabaseService();
      final manager = TelemetryManager(bleService: ble, gpsService: gps, dbService: db);

      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(telemetryManager: manager),
      ));

      await tester.pumpAndSettle();

      // Find section header
      expect(find.text('Diagnostika jednotky'), findsOneWidget);

      // Verify truthful em-dash displays when disconnected
      expect(find.text('MicroSD záznam'), findsOneWidget);
      expect(find.text('Senzor IMU (BNO085)'), findsOneWidget);
      expect(find.text('Napětí baterie'), findsOneWidget);
      expect(find.text('Palubní sběrnice'), findsOneWidget);
      expect(find.text('—'), findsWidgets);

      manager.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('BLE Chunked Sync Protocol Tests', () {
    test('checkOfflineLogs parses file list from mock queue', () async {
      final ble = BleService();
      ble.enableMockMode(true);
      ble.setMockOfflineLogs([
        'timestamp_ms,lean_angle_deg\n0,0.0\n',
        'timestamp_ms,lean_angle_deg\n0,5.0\n'
      ]);

      final files = await ble.checkOfflineLogs();
      expect(files.length, 2);
      expect(files[0], 'LOG_0001.CSV');
      expect(files[1], 'LOG_0002.CSV');
    });

    test('downloadOfflineLog returns CSV content and acknowledgeOfflineLogSync dequeues it', () async {
      final ble = BleService();
      ble.enableMockMode(true);
      const csvData = 'timestamp_ms,lean_angle_deg\n0,0.0\n10,2.5\n';
      ble.setMockOfflineLogs([csvData]);

      final downloaded = await ble.downloadOfflineLog('LOG_0001.CSV');
      expect(downloaded, csvData);

      final ack = await ble.acknowledgeOfflineLogSync('LOG_0001.CSV');
      expect(ack, isTrue);

      final remaining = await ble.checkOfflineLogs();
      expect(remaining, isEmpty);
    });

    test('TelemetryPacket getters reflect statusFlags truthfully', () {
      final pktActive = TelemetryPacket(
        timestampMs: 1000,
        leanAngleDeg: 0,
        pitchDeg: 0,
        accelXG: 0,
        accelYG: 0,
        accelZG: 1,
        gyroXDps: 0,
        gyroYDps: 0,
        gyroZDps: 0,
        engineRpm: 5000,
        vehicleSpeedKmh: 80,
        throttlePosPct: 40,
        coolantTempC: 85,
        gear: 4,
        batteryVoltage: 14.2,
        statusFlags: 0x0B, // SD_READY (bit 0) | ENGINE_RUNNING (bit 1) | IMU_READY (bit 3)
      );

      expect(pktActive.isSdCardMounted, isTrue);
      expect(pktActive.isEngineRunning, isTrue);
      expect(pktActive.isImuCalibrated, isTrue);
      expect(pktActive.isObdConnected, isTrue);

      final pktInactive = pktActive.copyWith(statusFlags: 0, engineRpm: 0, vehicleSpeedKmh: 0);
      expect(pktInactive.isSdCardMounted, isFalse);
      expect(pktInactive.isEngineRunning, isFalse);
      expect(pktInactive.isImuCalibrated, isFalse);
      expect(pktInactive.isObdConnected, isFalse);
    });
  });
}

class _FakeLapDbService extends DatabaseService {
  _FakeLapDbService() : super.forTesting();

  @override
  Future<List<FusedSample>> getSamplesForSession(int sessionId) async {
    return [
      // Crossing 1
      FusedSample(
        sessionId: sessionId,
        timestampMs: 10000,
        recordedAt: DateTime.now(),
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 10000,
        vehicleSpeedKmh: 180,
        throttlePosPct: 100,
        coolantTempC: 85,
        gear: 5,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444350,
        altitude: 380.0,
        gpsSpeedKmh: 180.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
      FusedSample(
        sessionId: sessionId,
        timestampMs: 10200,
        recordedAt: DateTime.now(),
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 10200,
        vehicleSpeedKmh: 182,
        throttlePosPct: 100,
        coolantTempC: 85,
        gear: 5,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444150,
        altitude: 380.0,
        gpsSpeedKmh: 182.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
      // Crossing 2
      FusedSample(
        sessionId: sessionId,
        timestampMs: 130000,
        recordedAt: DateTime.now(),
        leanAngleDeg: 45.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 1.1,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 10500,
        vehicleSpeedKmh: 188,
        throttlePosPct: 100,
        coolantTempC: 86,
        gear: 5,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444350,
        altitude: 380.0,
        gpsSpeedKmh: 188.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
      FusedSample(
        sessionId: sessionId,
        timestampMs: 130200,
        recordedAt: DateTime.now(),
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 10600,
        vehicleSpeedKmh: 190,
        throttlePosPct: 100,
        coolantTempC: 86,
        gear: 5,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444150,
        altitude: 380.0,
        gpsSpeedKmh: 190.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
      // Crossing 3
      FusedSample(
        sessionId: sessionId,
        timestampMs: 248000,
        recordedAt: DateTime.now(),
        leanAngleDeg: -49.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 1.2,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 11000,
        vehicleSpeedKmh: 200,
        throttlePosPct: 100,
        coolantTempC: 87,
        gear: 6,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444350,
        altitude: 380.0,
        gpsSpeedKmh: 200.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
      FusedSample(
        sessionId: sessionId,
        timestampMs: 248200,
        recordedAt: DateTime.now(),
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 11200,
        vehicleSpeedKmh: 202,
        throttlePosPct: 100,
        coolantTempC: 87,
        gear: 6,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444150,
        altitude: 380.0,
        gpsSpeedKmh: 202.0,
        bearing: 268.0,
        gpsAccuracyMeters: 1.0,
      ),
    ];
  }
}
