import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motologger/core/constants/ble_constants.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/can_learning_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/lap_timer_service.dart';
import 'package:motologger/services/telemetry_manager.dart';

class MockTestDatabaseService extends DatabaseService {
  MockTestDatabaseService() : super.forTesting();

  @override
  Future<int> startSession(String title) async => 1;

  @override
  Future<void> updateSession(dynamic session) async {}

  @override
  Future<void> insertSampleBatch(List<FusedSample> samples) async {}

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> saveSetting(String key, String value) async {}
}

class ControlledBleService extends BleService {
  final _telemetryCtrl = StreamController<TelemetryPacket>.broadcast();

  @override
  Stream<TelemetryPacket> get telemetryStream => _telemetryCtrl.stream;

  void emitPacket(TelemetryPacket packet) {
    _telemetryCtrl.add(packet);
  }

  @override
  void dispose() {
    _telemetryCtrl.close();
    super.dispose();
  }
}

class ControlledGpsService extends GpsService {
  final _posCtrl = StreamController<Position>.broadcast();
  Position? _pos;

  @override
  Stream<Position> get positionStream => _posCtrl.stream;

  @override
  Position? get lastPosition => _pos;

  void emitPosition({
    required double lat,
    required double lon,
    required double heading,
    double speedMps = 40.0,
  }) {
    final p = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 380.0,
      altitudeAccuracy: 1.0,
      heading: heading,
      headingAccuracy: 1.0,
      speed: speedMps,
      speedAccuracy: 0.5,
    );
    _pos = p;
    _posCtrl.add(p);
  }

  @override
  void dispose() {
    _posCtrl.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CAN Sniffer & BLE Protocol Tests', () {
    test('BleConstants contains sniffer command and response codes', () {
      expect(BleConstants.cmdCanSnifferMode, equals(0x40));
      expect(BleConstants.respCanRawFrame, equals(0xC0));
    });

    test('BleService decodes 14-byte 0xC0 respCanRawFrame binary notification', () async {
      final bleService = BleService();
      final received = <CapturedCanFrame>[];
      final sub = bleService.rawCanFrameStream.listen(received.add);

      final bd = ByteData(14);
      bd.setUint8(0, BleConstants.respCanRawFrame); // 0xC0
      bd.setUint32(1, 0x00000244, Endian.little);   // CAN ID 0x244
      bd.setUint8(5, 8);                            // DLC = 8
      final payload = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];
      for (int i = 0; i < 8; i++) {
        bd.setUint8(6 + i, payload[i]);
      }

      bleService.handleCommandResponseForTest(bd.buffer.asUint8List());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received.first.canId, equals(0x244));
      expect(received.first.data.length, equals(8));
      expect(received.first.data, equals(payload));

      await sub.cancel();
      bleService.dispose();
    });

    test('BleService mock mode supports setCanSnifferMode and raw CAN frames', () async {
      final bleService = BleService();
      bleService.enableMockMode(true);

      final success = await bleService.setCanSnifferMode(true);
      expect(success, isTrue);
      expect(bleService.isCanSnifferActive, isTrue);

      final disabled = await bleService.setCanSnifferMode(false);
      expect(disabled, isTrue);
      expect(bleService.isCanSnifferActive, isFalse);

      bleService.dispose();
    });

    test('BleService sendCanProfileMode includes baudrate in payload', () async {
      final bleService = BleService();
      bleService.enableMockMode(true);

      final ok250 = await bleService.sendCanProfileMode(isCustomActive: true, baudrateKbps: 250);
      expect(ok250, isTrue);

      final ok500 = await bleService.sendCanProfileMode(isCustomActive: true, baudrateKbps: 500);
      expect(ok500, isTrue);

      final ok1000 = await bleService.sendCanProfileMode(isCustomActive: true, baudrateKbps: 1000);
      expect(ok1000, isTrue);

      bleService.dispose();
    });
  });

  group('CanLearningService & Sniffer Integration', () {
    test('CanLearningService toggles sniffer and ingests raw frames', () async {
      final bleService = BleService();
      final gpsService = GpsService();
      bleService.enableMockMode(true);
      gpsService.enableMockMode(true);

      final service = CanLearningService(
        bleService: bleService,
        gpsService: gpsService,
      );

      service.startRecording();
      expect(service.isRecording, isTrue);
      expect(bleService.isCanSnifferActive, isTrue);

      // Ingest sample CAN frame
      service.ingestCanFrame(0x1F0, [0x25, 0x10, 0x07, 0xD0, 0x00, 0x00, 0x00, 0x00]);
      expect(service.capturedFrameCount, greaterThanOrEqualTo(1));
      expect(service.uniqueCanIdCount, greaterThanOrEqualTo(1));

      service.stopRecording();
      expect(service.isRecording, isFalse);
      expect(bleService.isCanSnifferActive, isFalse);

      service.dispose();
      bleService.dispose();
      gpsService.dispose();
    });
  });

  group('Custom Circuit & Single Segment Crossing Detection', () {
    test('createCustomCircuitFromPosition generates valid perpendicular gate', () {
      final gate = LapTimerService.createCustomCircuitFromPosition(
        lat: 49.203875,
        lon: 16.444250,
        headingDeg: 268.0,
        name: 'Vlastní cíl Brno',
        halfWidthMeters: 30.0,
      );

      expect(gate.name, equals('Vlastní cíl Brno'));
      expect(gate.centerLat, equals(49.203875));
      expect(gate.centerLon, equals(16.444250));
      expect(gate.expectedHeadingDeg, equals(268.0));
      expect(gate.p1Lat, isNot(equals(gate.p2Lat)));
    });

    test('checkSingleSegmentCrossing detects crossing in correct direction', () {
      // Automotodrom Brno finish line: East to West (heading ~268°)
      final gate = LapTimerService.knownCircuits.first;

      // Sample 1: East of line
      final prev = FusedSample(
        sessionId: 1,
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
      );

      // Sample 2: West of line
      final curr = FusedSample(
        sessionId: 1,
        timestampMs: 10500,
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
      );

      final crossing = LapTimerService.checkSingleSegmentCrossing(prev, curr, gate);
      expect(crossing, isNotNull);
      expect(crossing!.timestampMs, inInclusiveRange(10000, 10500));
    });

    test('checkSingleSegmentCrossing rejects reverse direction crossing', () {
      final gate = LapTimerService.knownCircuits.first;

      // Travelling backwards (West -> East, bearing 88°)
      final prev = FusedSample(
        sessionId: 1,
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
        engineRpm: 5000,
        vehicleSpeedKmh: 50,
        throttlePosPct: 20,
        coolantTempC: 85,
        gear: 2,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444150,
        altitude: 380.0,
        gpsSpeedKmh: 50.0,
        bearing: 88.0,
        gpsAccuracyMeters: 1.0,
      );

      final curr = FusedSample(
        sessionId: 1,
        timestampMs: 10500,
        recordedAt: DateTime.now(),
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 5000,
        vehicleSpeedKmh: 50,
        throttlePosPct: 20,
        coolantTempC: 85,
        gear: 2,
        batteryVoltage: 14.2,
        latitude: 49.203875,
        longitude: 16.444350,
        altitude: 380.0,
        gpsSpeedKmh: 50.0,
        bearing: 88.0,
        gpsAccuracyMeters: 1.0,
      );

      final crossing = LapTimerService.checkSingleSegmentCrossing(prev, curr, gate);
      expect(crossing, isNull);
    });
  });

  group('TelemetryManager Live Lap State', () {
    test('markCustomFinishLineHere sets activeCircuit and triggers live laps with delta', () async {
      final ble = ControlledBleService();
      final gps = ControlledGpsService();
      final db = MockTestDatabaseService();

      final manager = TelemetryManager(
        bleService: ble,
        gpsService: gps,
        dbService: db,
      );

      await manager.startRecording('Track Session');

      // Initial position at gate center (49.203875, 16.444250), heading West (268°)
      gps.emitPosition(lat: 49.203875, lon: 16.444250, heading: 268.0);
      ble.emitPacket(TelemetryPacket.initial().copyWith(timestampMs: 1000, vehicleSpeedKmh: 160));
      await Future.delayed(const Duration(milliseconds: 10));

      manager.markCustomFinishLineHere();
      expect(manager.activeCircuit, isNotNull);
      expect(manager.activeCircuit!.name, equals('Vlastní cíl'));
      expect(manager.currentLapNumber, equals(1));
      expect(manager.liveLaps, isEmpty);

      // Complete Lap 1 (~60 seconds later: cross from East 16.444350 to West 16.444150)
      gps.emitPosition(lat: 49.203875, lon: 16.444350, heading: 268.0);
      ble.emitPacket(TelemetryPacket.initial().copyWith(timestampMs: 60800, vehicleSpeedKmh: 175));
      await Future.delayed(const Duration(milliseconds: 10));

      gps.emitPosition(lat: 49.203875, lon: 16.444150, heading: 268.0);
      ble.emitPacket(TelemetryPacket.initial().copyWith(timestampMs: 61200, vehicleSpeedKmh: 180));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(manager.currentLapNumber, equals(2));
      expect(manager.liveLaps.length, equals(1));
      expect(manager.lastLapDeltaSeconds, isNull);

      // Complete Lap 2 (~59 seconds later - faster lap! Should produce negative deltaSeconds)
      gps.emitPosition(lat: 49.203875, lon: 16.444350, heading: 268.0);
      ble.emitPacket(TelemetryPacket.initial().copyWith(timestampMs: 119800, vehicleSpeedKmh: 185));
      await Future.delayed(const Duration(milliseconds: 10));

      gps.emitPosition(lat: 49.203875, lon: 16.444150, heading: 268.0);
      ble.emitPacket(TelemetryPacket.initial().copyWith(timestampMs: 120200, vehicleSpeedKmh: 190));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(manager.currentLapNumber, equals(3));
      expect(manager.liveLaps.length, equals(2));
      expect(manager.lastLapDeltaSeconds, isNotNull);
      expect(manager.lastLapDeltaSeconds!, lessThan(0.0));

      manager.dispose();
      ble.dispose();
      gps.dispose();
    });
  });
}

