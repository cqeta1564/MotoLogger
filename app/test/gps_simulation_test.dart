import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/models/fused_sample.dart';

class _FakeDbForGpsTest extends DatabaseService {
  final List<RideSession> sessions = [];
  final List<FusedSample> samples = [];

  _FakeDbForGpsTest() : super.forTesting();

  @override
  Future<int> startSession(String title) async {
    final id = sessions.length + 1;
    sessions.add(RideSession(id: id, title: title, startTime: DateTime.now()));
    return id;
  }

  @override
  Future<void> updateSession(RideSession session) async {
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      sessions[idx] = session;
    }
  }

  @override
  Future<void> insertSampleBatch(List<FusedSample> newSamples) async {
    samples.addAll(newSamples);
  }

  @override
  Future<List<RideSession>> getAllSessions() async => List.unmodifiable(sessions);

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> saveSetting(String key, String value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpsService Simulation Tests', () {
    late GpsService gpsService;

    setUp(() {
      gpsService = GpsService();
    });

    tearDown(() {
      gpsService.dispose();
    });

    test('enableMockMode generates initial position on Masaryk Circuit', () async {
      expect(gpsService.isMockMode, isFalse);
      expect(gpsService.lastPosition, isNull);

      final positions = <Position>[];
      final sub = gpsService.positionStream.listen(positions.add);

      gpsService.enableMockMode(true);
      expect(gpsService.isMockMode, isTrue);

      // Initial position should be emitted immediately
      expect(gpsService.lastPosition, isNotNull);
      final p0 = gpsService.lastPosition!;
      expect(p0.latitude, closeTo(49.204, 0.005));
      expect(p0.longitude, closeTo(16.448, 0.005));
      expect(p0.altitude, greaterThan(380.0));
      expect(p0.speed, greaterThan(0.0));
      expect(p0.heading, inInclusiveRange(0.0, 360.0));
      expect(p0.isMocked, isTrue);

      // Wait for at least 2 more ticks (200ms)
      await Future.delayed(const Duration(milliseconds: 250));

      expect(positions.length, greaterThanOrEqualTo(2));
      final p1 = positions.last;
      expect(p1.latitude, isNot(0.0));
      expect(p1.longitude, isNot(0.0));

      gpsService.enableMockMode(false);
      expect(gpsService.isMockMode, isFalse);

      await sub.cancel();
    });

    test('disabling mock mode stops stream emission', () async {
      gpsService.enableMockMode(true);
      expect(gpsService.isMockMode, isTrue);

      await Future.delayed(const Duration(milliseconds: 150));
      final countBefore = gpsService.lastPosition;

      gpsService.enableMockMode(false);
      expect(gpsService.isMockMode, isFalse);

      await Future.delayed(const Duration(milliseconds: 250));
      // Position should not have changed after stopping
      expect(gpsService.lastPosition, equals(countBefore));
    });
  });

  group('TelemetryManager Simulation Coordination Tests', () {
    late BleService bleService;
    late GpsService gpsService;
    late _FakeDbForGpsTest fakeDb;
    late TelemetryManager telemetryManager;

    setUp(() {
      bleService = BleService();
      gpsService = GpsService();
      fakeDb = _FakeDbForGpsTest();
      telemetryManager = TelemetryManager(
        bleService: bleService,
        gpsService: gpsService,
        dbService: fakeDb,
      );
    });

    tearDown(() {
      telemetryManager.dispose();
      bleService.dispose();
      gpsService.dispose();
    });

    test('setSimulationMode toggles both BLE and GPS simultaneously', () async {
      expect(telemetryManager.isSimulationMode, isFalse);
      expect(bleService.isMockMode, isFalse);
      expect(gpsService.isMockMode, isFalse);

      telemetryManager.setSimulationMode(true);
      expect(telemetryManager.isSimulationMode, isTrue);
      expect(bleService.isMockMode, isTrue);
      expect(gpsService.isMockMode, isTrue);

      // Wait 150ms to accumulate mock packets and positions
      await Future.delayed(const Duration(milliseconds: 150));

      expect(telemetryManager.latestPosition, isNotNull);
      expect(telemetryManager.latestPosition!.latitude, closeTo(49.204, 0.01));
      expect(telemetryManager.latestPacket.vehicleSpeedKmh, greaterThan(0));

      telemetryManager.setSimulationMode(false);
      expect(telemetryManager.isSimulationMode, isFalse);
      expect(bleService.isMockMode, isFalse);
      expect(gpsService.isMockMode, isFalse);
    });

    test('FusedSample during simulation recording contains authentic GPS coordinates', () async {
      telemetryManager.setSimulationMode(true);
      await telemetryManager.startRecording('Brno Circuit Simulation Test');

      // Let simulation run for 300ms
      await Future.delayed(const Duration(milliseconds: 300));

      await telemetryManager.stopRecording();

      expect(fakeDb.sessions.isNotEmpty, isTrue);
      final savedSession = fakeDb.sessions.first;
      expect(savedSession.sampleCount, greaterThan(0));
      expect(savedSession.totalDistanceKm, greaterThanOrEqualTo(0.0));

      expect(fakeDb.samples.isNotEmpty, isTrue);
      final firstSample = fakeDb.samples.first;
      expect(firstSample.latitude, closeTo(49.204, 0.01));
      expect(firstSample.longitude, closeTo(16.448, 0.01));
      expect(firstSample.altitude, greaterThan(350.0));
      expect(firstSample.gpsSpeedKmh, greaterThan(0.0));
      expect(firstSample.bearing, inInclusiveRange(0.0, 360.0));
    });
  });
}
