import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/ui/widgets/gg_friction_card.dart';
import 'package:motologger/ui/widgets/gps_track_map_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSession = RideSession(
    id: 42,
    title: 'Test & Ride <Fast "Curves">',
    startTime: DateTime.utc(2026, 9, 10, 14, 0, 0),
    endTime: DateTime.utc(2026, 9, 10, 14, 30, 0),
    maxLeanLeftDeg: 48.2,
    maxLeanRightDeg: 51.7,
    topSpeedKmh: 145.0,
    maxGForce: 1.25,
    totalDistanceKm: 25.5,
    sampleCount: 3,
  );

  final List<FusedSample> testSamples = [
    // Sample 1: Valid coordinate, hard braking + left turn
    FusedSample(
      sessionId: 42,
      timestampMs: 1000,
      recordedAt: DateTime.utc(2026, 9, 10, 14, 0, 1),
      latitude: 50.0755,
      longitude: 14.4378,
      altitude: 235.0,
      gpsSpeedKmh: 72.0, // 20 m/s
      bearing: 90.0,
      gpsAccuracyMeters: 3.5,
      leanAngleDeg: -35.5, // Left lean
      pitchDeg: -4.0,
      accelXG: -0.65, // Left lateral G
      accelYG: -0.85, // Heavy braking G
      accelZG: 0.98,
      gyroXDps: 0.0,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      vehicleSpeedKmh: 71,
      engineRpm: 6500,
      throttlePosPct: 15,
      gear: 3,
      coolantTempC: 88,
      batteryVoltage: 14.2,
    ),
    // Sample 2: Valid coordinate, right lean + acceleration
    FusedSample(
      sessionId: 42,
      timestampMs: 2000,
      recordedAt: DateTime.utc(2026, 9, 10, 14, 0, 2),
      latitude: 50.0760,
      longitude: 14.4385,
      altitude: 238.0,
      gpsSpeedKmh: 108.0, // 30 m/s
      bearing: 110.0,
      gpsAccuracyMeters: 2.8,
      leanAngleDeg: 46.0, // Right lean (Apex)
      pitchDeg: 6.5,
      accelXG: 0.88, // Right lateral G
      accelYG: 0.72, // Acceleration G
      accelZG: 1.05,
      gyroXDps: 0.0,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      vehicleSpeedKmh: 107,
      engineRpm: 9200,
      throttlePosPct: 90,
      gear: 4,
      coolantTempC: 91,
      batteryVoltage: 14.3,
    ),
    // Sample 3: Zero GPS coordinate (indoor / no GPS lock)
    FusedSample(
      sessionId: 42,
      timestampMs: 3000,
      recordedAt: DateTime.utc(2026, 9, 10, 14, 0, 3),
      latitude: 0.0,
      longitude: 0.0,
      altitude: 0.0,
      gpsSpeedKmh: 0.0,
      bearing: 0.0,
      gpsAccuracyMeters: 50.0,
      leanAngleDeg: 0.0,
      pitchDeg: 0.0,
      accelXG: 0.0,
      accelYG: 0.0,
      accelZG: 1.0,
      gyroXDps: 0.0,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      vehicleSpeedKmh: 0,
      engineRpm: 1200,
      throttlePosPct: 0,
      gear: 0,
      coolantTempC: 85,
      batteryVoltage: 14.1,
    ),
  ];

  group('DatabaseService GPX & CSV Export Tests', () {
    test('generateGpxString produces valid GPX 1.1 with extensions and XML escaping', () {
      final gpx = DatabaseService.instance.generateGpxString(
        session: testSession,
        samples: testSamples,
      );

      // Verify XML header and root namespaces
      expect(gpx.startsWith('<?xml version="1.0" encoding="UTF-8"?>'), isTrue);
      expect(gpx.contains('<gpx version="1.1"'), isTrue);
      expect(gpx.contains('xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"'), isTrue);
      expect(gpx.contains('xmlns:motologger="http://motologger.org/gpx/1.0"'), isTrue);

      // Verify escaped metadata title
      expect(gpx.contains('<name>Test &amp; Ride &lt;Fast &quot;Curves&quot;&gt;</name>'), isTrue);

      // Verify trackpoints (sample 1 & 2 included, sample 3 with 0,0 excluded)
      expect(gpx.contains('<trkpt lat="50.0755" lon="14.4378">'), isTrue);
      expect(gpx.contains('<trkpt lat="50.076" lon="14.4385">'), isTrue);
      expect(gpx.contains('<trkpt lat="0.0" lon="0.0">'), isFalse);

      // Verify speed in m/s (72 km/h / 3.6 = 20.00 m/s)
      expect(gpx.contains('<gpxtpx:speed>20.00</gpxtpx:speed>'), isTrue);
      expect(gpx.contains('<gpxtpx:speed>30.00</gpxtpx:speed>'), isTrue);

      // Verify MotoLogger extensions
      expect(gpx.contains('<motologger:lean_angle_deg>-35.50</motologger:lean_angle_deg>'), isTrue);
      expect(gpx.contains('<motologger:lean_angle_deg>46.00</motologger:lean_angle_deg>'), isTrue);
      expect(gpx.contains('<motologger:engine_rpm>6500</motologger:engine_rpm>'), isTrue);
      expect(gpx.contains('<motologger:throttle_pos_pct>90</motologger:throttle_pos_pct>'), isTrue);
      expect(gpx.contains('<motologger:accel_x_g>-0.650</motologger:accel_x_g>'), isTrue);
      expect(gpx.contains('<motologger:accel_y_g>-0.850</motologger:accel_y_g>'), isTrue);
    });

    test('generateCsvString produces well-formatted CSV with headers and data rows', () {
      final csv = DatabaseService.instance.generateCsvString(samples: testSamples);

      final lines = csv.trim().split('\n');
      expect(lines.length, equals(4)); // Header + 3 samples
      expect(lines.first.startsWith('timestamp_ms,recorded_at,latitude,longitude,'), isTrue);

      // Verify first sample values
      expect(lines[1].contains('50.0755,14.4378,235.0,72.0,90.0,-35.50'), isTrue);
    });
  });

  group('GpsTrackMapCard Widget Tests', () {
    testWidgets('Renders GPS trajectory map card with mode toggle buttons and legend', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GpsTrackMapCard(samples: testSamples),
            ),
          ),
        ),
      );

      // Verify title and subtitle
      expect(find.text('TRASA JÍZDY (GPS)'), findsOneWidget);
      expect(find.text('Barevná telemetrie v zatáčkách'), findsOneWidget);

      // Mode toggles
      expect(find.text('Klopení'), findsOneWidget);
      expect(find.text('Rychlost'), findsOneWidget);

      // Lean legend is shown initially
      expect(find.text('Přímá (<15°)'), findsOneWidget);
      expect(find.text('Limit (>45°)'), findsOneWidget);

      // Switch to Speed mode
      await tester.tap(find.text('Rychlost'));
      await tester.pumpAndSettle();

      // CustomPaint canvas is present
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renders empty state message when no valid GPS coordinates are present', (tester) async {
      final List<FusedSample> emptyGpsSamples = [
        FusedSample(
          sessionId: 1,
          timestampMs: 100,
          recordedAt: DateTime.now(),
          latitude: 0.0,
          longitude: 0.0,
          altitude: 0.0,
          gpsSpeedKmh: 0.0,
          bearing: 0.0,
          gpsAccuracyMeters: 10.0,
          leanAngleDeg: 10.0,
          pitchDeg: 0.0,
          accelXG: 0.0,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          vehicleSpeedKmh: 0,
          engineRpm: 1000,
          throttlePosPct: 0,
          gear: 1,
          coolantTempC: 80,
          batteryVoltage: 14.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpsTrackMapCard(samples: emptyGpsSamples),
          ),
        ),
      );

      expect(find.text('Žádná GPS data pro vykreslení trasy'), findsOneWidget);
      expect(find.text('Při této jízdě nebyl k dispozici signál satelitů.'), findsOneWidget);
    });
  });

  group('GgFrictionCard Widget Tests', () {
    testWidgets('Renders G-G friction envelope and calculates peak accelerations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GgFrictionCard(samples: testSamples),
            ),
          ),
        ),
      );

      // Verify header and Apple aesthetic
      expect(find.text('FRIKČNÍ DIAGRAM G-G'), findsOneWidget);
      expect(find.text('Využití přilnavosti pneumatik (brzdy vs. zatáčení)'), findsOneWidget);

      // 4 Metric cards
      expect(find.text('Max. brzdění'), findsOneWidget);
      expect(find.text('Max. zrychlení'), findsOneWidget);
      expect(find.text('Levý náklon G'), findsOneWidget);
      expect(find.text('Pravý náklon G'), findsOneWidget);

      // Peak values:
      // Max braking: sample 1 had accelYG = -0.85 -> 0.85 G
      // Max accel: sample 2 had accelYG = 0.72 -> +0.72 G
      // Max left: sample 1 had accelXG = -0.65 -> 0.65 G
      // Max right: sample 2 had accelXG = 0.88 -> 0.88 G
      expect(find.text('0.85 G'), findsOneWidget);
      expect(find.text('+0.72 G'), findsOneWidget);
      expect(find.text('0.65 G'), findsOneWidget);
      expect(find.text('0.88 G'), findsOneWidget);
    });

    testWidgets('Handles empty sample list gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GgFrictionCard(samples: []),
          ),
        ),
      );

      expect(find.text('FRIKČNÍ DIAGRAM G-G'), findsOneWidget);
      expect(find.text('0.00 G'), findsNWidgets(3)); // brake, left, right
      expect(find.text('+0.00 G'), findsOneWidget); // accel
    });
  });
}
