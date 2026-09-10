import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/history/history_screen.dart';
import 'package:motologger/ui/widgets/season_summary_card.dart';

class FakeDatabaseService extends DatabaseService {
  final List<RideSession> _sessions = [];
  final Map<String, String> _settings = {};

  FakeDatabaseService({List<RideSession>? initialSessions}) : super.forTesting() {
    if (initialSessions != null) {
      _sessions.addAll(initialSessions);
    }
  }

  @override
  Future<List<RideSession>> getAllSessions() async => List.unmodifiable(_sessions);

  @override
  Future<RideSession> importRideFromCsv({
    required String csvContent,
    String? defaultTitle,
    DateTime? fileTimestamp,
  }) async {
    final parsed = DatabaseService.parseRideCsv(
      csvContent: csvContent,
      defaultTitle: defaultTitle,
      fileTimestamp: fileTimestamp,
    );
    final saved = parsed.session.copyWith(id: _sessions.length + 1);
    _sessions.insert(0, saved);
    return saved;
  }

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
  TestWidgetsFlutterBinding.ensureInitialized();

  const rawSdCsv = '''
timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,v_bat,engine_rpm,vehicle_speed_kmh,throttle_pos_pct,coolant_temp_c,gear
#CAN,1000000,0x1F0,8,17,70,03,E8,00,00,12,34
1000,-35.5,2.1,-0.450,-0.850,0.980,12.5,0.0,0.0,14.2,6500,72,25.0,88,3
2000,48.2,3.4,0.650,0.720,1.020,15.2,0.0,0.0,14.3,9200,126,85.0,91,4
3000,10.0,1.0,0.100,0.200,1.000,2.0,0.0,0.0,14.2,4000,50,10.0,86,2
''';

  group('DatabaseService CSV Import & Parsing Tests', () {
    test('parseRideCsv parses raw MicroSD log and computes metrics correctly', () {
      final parsed = DatabaseService.parseRideCsv(
        csvContent: rawSdCsv,
        defaultTitle: 'Test SD Ride',
      );

      expect(parsed.session.title, equals('Test SD Ride'));
      expect(parsed.samples.length, equals(3));

      // Peak Lean & Speed
      expect(parsed.session.maxLeanLeftDeg, equals(35.5));
      expect(parsed.session.maxLeanRightDeg, equals(48.2));
      expect(parsed.session.topSpeedKmh, equals(126.0));

      // Resultant G force: sample 1: sqrt((-0.45)^2 + (-0.85)^2) = sqrt(0.2025 + 0.7225) = sqrt(0.925) ~= 0.961
      // sample 2: sqrt((0.65)^2 + (0.72)^2) = sqrt(0.4225 + 0.5184) = sqrt(0.9409) = 0.970
      expect(parsed.session.maxGForce, closeTo(0.97, 0.02));

      // Sample details
      expect(parsed.samples[0].leanAngleDeg, equals(-35.5));
      expect(parsed.samples[0].vehicleSpeedKmh, equals(72));
      expect(parsed.samples[0].gear, equals(3));
      expect(parsed.samples[1].engineRpm, equals(9200));

      // Distance integration: between 1s and 3s
      expect(parsed.session.totalDistanceKm, greaterThan(0.0));
    });

    test('parseRideCsv throws FormatException on empty or header-only CSV', () {
      expect(
        () => DatabaseService.parseRideCsv(csvContent: ''),
        throwsFormatException,
      );

      expect(
        () => DatabaseService.parseRideCsv(csvContent: 'no,proper,header,here'),
        throwsFormatException,
      );

      const headerOnly = 'timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g\n';
      expect(
        () => DatabaseService.parseRideCsv(csvContent: headerOnly),
        throwsFormatException,
      );
    });

    test('parseRideCsv supports exported CSV format with GPS coordinates', () {
      const exportedCsv = '''
timestamp_ms,recorded_at,latitude,longitude,altitude_m,gps_speed_kmh,bearing_deg,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,vehicle_speed_kmh,engine_rpm,throttle_pos_pct,coolant_temp_c,gear,battery_voltage
1000,2026-09-10T14:00:01.000Z,50.0755,14.4378,235.0,72.0,90.0,-30.0,0.0,0.1,0.2,1.0,0.0,0.0,0.0,70,6000,20,85,3,14.2
2000,2026-09-10T14:00:02.000Z,50.0760,14.4385,238.0,90.0,110.0,42.0,0.0,0.2,0.3,1.0,0.0,0.0,0.0,90,8000,50,88,4,14.3
''';

      final parsed = DatabaseService.parseRideCsv(csvContent: exportedCsv);
      expect(parsed.samples.length, equals(2));
      expect(parsed.samples[0].latitude, equals(50.0755));
      expect(parsed.samples[0].longitude, equals(14.4378));
      expect(parsed.samples[0].gpsSpeedKmh, equals(72.0));
      expect(parsed.session.maxLeanRightDeg, equals(42.0));
    });
  });

  group('SeasonStats Tests', () {
    final s1 = RideSession(
      id: 1,
      title: 'Ride 1',
      startTime: DateTime.utc(2026, 5, 1, 10, 0),
      endTime: DateTime.utc(2026, 5, 1, 11, 30), // 1.5h
      totalDistanceKm: 65.5,
      maxLeanLeftDeg: 46.2,
      maxLeanRightDeg: 44.0,
      topSpeedKmh: 135.0,
      sampleCount: 5000,
    );

    final s2 = RideSession(
      id: 2,
      title: 'Ride 2',
      startTime: DateTime.utc(2026, 6, 1, 14, 0),
      endTime: DateTime.utc(2026, 6, 1, 15, 0), // 1.0h
      totalDistanceKm: 45.2,
      maxLeanLeftDeg: 42.0,
      maxLeanRightDeg: 51.5,
      topSpeedKmh: 162.0,
      sampleCount: 3500,
    );

    test('Calculates aggregate season statistics accurately', () {
      final stats = SeasonStats.fromSessions([s1, s2]);

      expect(stats.totalRides, equals(2));
      expect(stats.totalDistanceKm, closeTo(110.7, 0.01));
      expect(stats.totalDuration.inMinutes, equals(150)); // 2.5h
      expect(stats.maxLeanLeftDeg, equals(46.2));
      expect(stats.maxLeanRightDeg, equals(51.5));
      expect(stats.topSpeedKmh, equals(162.0));
    });

    test('Returns zeroes for empty session list', () {
      final empty = SeasonStats.fromSessions([]);
      expect(empty.totalRides, equals(0));
      expect(empty.totalDistanceKm, equals(0.0));
      expect(empty.totalDuration, equals(Duration.zero));
      expect(empty.maxLeanLeftDeg, equals(0.0));
      expect(empty.topSpeedKmh, equals(0.0));
    });
  });

  group('SeasonSummaryCard Widget Tests', () {
    testWidgets('Renders aggregate season metrics with Apple aesthetic', (tester) async {
      const stats = SeasonStats(
        totalRides: 14,
        totalDistanceKm: 1450.5,
        totalDuration: Duration(hours: 24, minutes: 30),
        maxLeanLeftDeg: 49.2,
        maxLeanRightDeg: 52.8,
        topSpeedKmh: 178.0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SeasonSummaryCard(stats: stats, selectedYear: 2026),
          ),
        ),
      );

      // Verify Header and Badges
      expect(find.text('SEZÓNNÍ SOUHRN'), findsOneWidget);
      expect(find.text('Sezóna 2026 • 14 jízd'), findsOneWidget);
      expect(find.text('1451 km'), findsOneWidget);

      // 4 Metrics
      expect(find.text('Celkový nájezd'), findsOneWidget);
      expect(find.text('1450.5 km'), findsOneWidget);

      expect(find.text('Čas v sedle'), findsOneWidget);
      expect(find.text('24 h 30 min'), findsOneWidget);

      expect(find.text('Rekord náklonu (L / P)'), findsOneWidget);
      expect(find.text('◀ 49.2° | 52.8° ▶'), findsOneWidget);

      expect(find.text('Maximální rychlost'), findsOneWidget);
      expect(find.text('178 km/h'), findsOneWidget);
    });
  });

  group('Automatic Sync & HistoryScreen Widget Tests', () {
    test('autoSyncOfflineSessions automatically imports un-synced logs on connection', () async {
      final fakeDb = FakeDatabaseService();
      final ble = BleService();
      final gps = GpsService();
      ble.enableMockMode(true);

      // Queue an offline session CSV into BleService mock queue
      ble.setMockOfflineLogs([rawSdCsv]);

      final telemetryMgr = TelemetryManager(
        bleService: ble,
        gpsService: gps,
        dbService: fakeDb,
      );

      // Trigger automatic sync
      final importedCount = await telemetryMgr.autoSyncOfflineSessions();

      expect(importedCount, equals(1));
      final all = await fakeDb.getAllSessions();
      expect(all.length, equals(1));
      expect(all.first.topSpeedKmh, equals(126.0));
      expect(all.first.maxLeanRightDeg, equals(48.2));
    });

    testWidgets('HistoryScreen renders season summary, sort controls, and session list', (tester) async {
      final testSessions = [
        RideSession(
          id: 1,
          title: 'Brno Circuit Fast',
          startTime: DateTime.utc(2026, 7, 10, 10, 0),
          totalDistanceKm: 42.0,
          topSpeedKmh: 195.0,
          maxLeanLeftDeg: 52.0,
          maxLeanRightDeg: 54.0,
          sampleCount: 1000,
        ),
        RideSession(
          id: 2,
          title: 'Sunday Alpine Pass',
          startTime: DateTime.utc(2026, 7, 11, 14, 0),
          totalDistanceKm: 120.0,
          topSpeedKmh: 130.0,
          maxLeanLeftDeg: 44.0,
          maxLeanRightDeg: 45.0,
          sampleCount: 2000,
        ),
      ];

      final fakeDb = FakeDatabaseService(initialSessions: testSessions);

      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Import button
      expect(find.text('Historie jízd'), findsOneWidget);
      expect(find.byIcon(Icons.sd_card_outlined), findsOneWidget);

      // Verify Season Summary Card
      expect(find.text('SEZÓNNÍ SOUHRN'), findsOneWidget);
      expect(find.text('162.0 km'), findsOneWidget); // 42 + 120

      // Verify Sort Controls
      expect(find.text('Nejnovější'), findsOneWidget);
      expect(find.text('Nejrychlejší'), findsOneWidget);
      expect(find.text('Největší náklon'), findsOneWidget);

      // Verify Session Titles rendered
      expect(find.text('Brno Circuit Fast'), findsOneWidget);
      expect(find.text('Sunday Alpine Pass'), findsOneWidget);

      // Switch sort to 'Nejrychlejší'
      await tester.tap(find.text('Nejrychlejší'));
      await tester.pumpAndSettle();

      // Filter via search
      await tester.enterText(find.byType(CupertinoSearchTextField), 'Brno');
      await tester.pumpAndSettle();

      expect(find.text('Brno Circuit Fast'), findsOneWidget);
      expect(find.text('Sunday Alpine Pass'), findsNothing);
    });
  });
}
