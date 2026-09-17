import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/ui/history/history_screen.dart';

class TestMockDatabaseService extends DatabaseService {
  final List<RideSession> _sessions = [];
  final Map<int, List<FusedSample>> _samples = {};

  TestMockDatabaseService({
    List<RideSession>? sessions,
    Map<int, List<FusedSample>>? samples,
  }) : super.forTesting() {
    if (sessions != null) _sessions.addAll(sessions);
    if (samples != null) _samples.addAll(samples);
  }

  @override
  Future<List<RideSession>> getAllSessions() async => List.unmodifiable(_sessions);

  @override
  Future<RideSession?> getSessionById(int id) async {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FusedSample>> getSamplesForSession(int sessionId) async {
    return _samples[sessionId] ?? [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSession = RideSession(
    id: 1,
    title: 'Automotodrom Brno - Stint 1',
    startTime: DateTime(2026, 9, 10, 14, 30, 0),
    endTime: DateTime(2026, 9, 10, 14, 45, 0),
    maxLeanLeftDeg: -48.5,
    maxLeanRightDeg: 51.2,
    topSpeedKmh: 215.0,
    maxGForce: 1.42,
    totalDistanceKm: 12.5,
    sampleCount: 3,
  );

  final List<FusedSample> testSamples = [
    FusedSample(
      sessionId: 1,
      timestampMs: 1000,
      recordedAt: DateTime(2026, 9, 10, 14, 30, 0),
      leanAngleDeg: 0.0,
      pitchDeg: 0.5,
      accelXG: 0.25,
      accelYG: 0.05,
      accelZG: 0.98,
      gyroXDps: 0.1,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      engineRpm: 4500,
      vehicleSpeedKmh: 60,
      throttlePosPct: 35,
      coolantTempC: 84,
      gear: 2,
      batteryVoltage: 14.2,
      latitude: 49.2038,
      longitude: 16.4442,
      altitude: 380.0,
      gpsSpeedKmh: 59.5,
      bearing: 120.0,
      gpsAccuracyMeters: 1.5,
    ),
    FusedSample(
      sessionId: 1,
      timestampMs: 1040,
      recordedAt: DateTime(2026, 9, 10, 14, 30, 0, 40),
      leanAngleDeg: -24.5,
      pitchDeg: 0.2,
      accelXG: 0.30,
      accelYG: 0.45,
      accelZG: 1.05,
      gyroXDps: -12.4,
      gyroYDps: 0.1,
      gyroZDps: 3.5,
      engineRpm: 6800,
      vehicleSpeedKmh: 95,
      throttlePosPct: 65,
      coolantTempC: 85,
      gear: 2,
      batteryVoltage: 14.3,
      latitude: 49.2040,
      longitude: 16.4445,
      altitude: 380.5,
      gpsSpeedKmh: 94.2,
      bearing: 122.0,
      gpsAccuracyMeters: 1.5,
    ),
    FusedSample(
      sessionId: 1,
      timestampMs: 1080,
      recordedAt: DateTime(2026, 9, 10, 14, 30, 0, 80),
      leanAngleDeg: -48.5,
      pitchDeg: -0.5,
      accelXG: -0.10,
      accelYG: 1.15,
      accelZG: 1.25,
      gyroXDps: -2.1,
      gyroYDps: 0.3,
      gyroZDps: 8.9,
      engineRpm: 9200,
      vehicleSpeedKmh: 110,
      throttlePosPct: 40,
      coolantTempC: 86,
      gear: 3,
      batteryVoltage: 14.1,
      latitude: 49.2043,
      longitude: 16.4449,
      altitude: 381.0,
      gpsSpeedKmh: 109.0,
      bearing: 130.0,
      gpsAccuracyMeters: 1.5,
    ),
  ];

  group('MoTeC i2 CSV Generation Tests', () {
    test('generateMotecCsvString creates compliant MoTeC header and channel rows', () {
      final db = TestMockDatabaseService();
      final csv = db.generateMotecCsvString(session: testSession, samples: testSamples);

      // Verify MoTeC metadata lines
      expect(csv, contains('"Format","MoTeC CSV File"'));
      expect(csv, contains('"Venue","Automotodrom Brno - Stint 1"'));
      expect(csv, contains('"Vehicle","MotoLogger Bike"'));
      expect(csv, contains('"Device","MotoLogger ESP32-S3"'));
      expect(csv, contains('"Sample Rate","25"'));

      // Verify two-row header: Channels and Units
      expect(csv, contains('"Time","Distance","GPS_Lat","GPS_Long"'));
      expect(csv, contains('"s","m","deg","deg"'));
      expect(csv, contains('"Engine_RPM","Vehicle_Speed"'));

      // Verify Time starts at 0.000s and relative timing
      expect(csv, contains('0.000,0.0,49.203800,16.444200'));
      expect(csv, contains('0.040,'));
      expect(csv, contains('0.080,'));
    });
  });

  group('RaceRender CSV Generation Tests', () {
    test('generateRaceRenderCsvString generates standard columns for auto-binding', () {
      final db = TestMockDatabaseService();
      final csv = db.generateRaceRenderCsvString(session: testSession, samples: testSamples);

      expect(csv, contains('Time,Distance,Latitude,Longitude,Altitude,Speed,Heading,Lean_Angle,Pitch_Angle,Lateral_G,Longitudinal_G,Vertical_G,Engine_RPM,Throttle,Gear,Coolant_Temp,Battery_Voltage'));
      expect(csv, contains('0.000,0.0,49.203800,16.444200,380.0,60.0,120.0,0.00,0.50,0.050,0.250,0.980,4500,35,2,84,14.20'));
      expect(csv, contains('0.080,'));
    });
  });

  group('Analysis README Generation Tests', () {
    test('generateAnalysisReadmeString contains guide for MoTeC and RaceRender', () {
      final db = TestMockDatabaseService();
      final readme = db.generateAnalysisReadmeString(sessions: [testSession]);

      expect(readme, contains('MotoLogger Telemetry Package - MoTeC i2 & RaceRender Analysis'));
      expect(readme, contains('1. NÁVOD PRO IMPORT DO MoTeC i2'));
      expect(readme, contains('2. NÁVOD PRO PŘEKRYV VIDEA V RaceRender'));
      expect(readme, contains('3. SLOVNÍK KANÁLŮ / CHANNEL DICTIONARY'));
      expect(readme, contains('Automotodrom Brno - Stint 1'));
    });
  });

  group('ZIP Package Creation Tests', () {
    test('exportPackageToZip creates valid zip containing MoTeC, RaceRender, GPX, and README', () async {
      final tempDir = await Directory.systemTemp.createTemp('motologger_zip_test_');
      final db = TestMockDatabaseService(
        sessions: [testSession],
        samples: {1: testSamples},
      );

      final zipPath = await db.exportPackageToZip(
        sessionIds: [1],
        targetDirectory: tempDir,
      );

      final zipFile = File(zipPath);
      expect(await zipFile.exists(), isTrue);

      // Unpack and verify contents
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final fileNames = archive.files.map((f) => f.name).toList();
      expect(fileNames, contains('README_ANALYSIS.txt'));
      expect(fileNames.any((name) => name.startsWith('MoTeC_i2/') && name.endsWith('_motec.csv')), isTrue);
      expect(fileNames.any((name) => name.startsWith('RaceRender/') && name.endsWith('_racerender.csv')), isTrue);
      expect(fileNames.any((name) => name.startsWith('RaceRender/') && name.endsWith('.gpx')), isTrue);
      expect(fileNames.any((name) => name.startsWith('Raw_Data/') && name.endsWith('_raw.csv')), isTrue);

      // Verify MoTeC file content within zip
      final motecFile = archive.files.firstWhere((f) => f.name.contains('_motec.csv'));
      final motecContent = utf8.decode(motecFile.content as List<int>);
      expect(motecContent, contains('"Format","MoTeC CSV File"'));

      // Clean up
      await tempDir.delete(recursive: true);
    });
  });

  group('HistoryScreen Selection Mode Widget Tests', () {
    testWidgets('Toggles selection mode, selects items, and shows bulk export dock', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = TestMockDatabaseService(
        sessions: [
          testSession,
          testSession.copyWith(id: 2, title: 'Most Circuit - Stint 2'),
        ],
        samples: {
          1: testSamples,
          2: testSamples,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(dbService: db),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sessions are rendered
      expect(find.text('Automotodrom Brno - Stint 1'), findsOneWidget);
      expect(find.text('Most Circuit - Stint 2'), findsOneWidget);

      // Enter selection mode via AppBar checklist icon
      final selectBtn = find.byTooltip('Vybrat jízdy');
      expect(selectBtn, findsOneWidget);
      await tester.tap(selectBtn);
      await tester.pumpAndSettle();

      // In selection mode:
      expect(find.text('Vybráno: 0'), findsOneWidget);
      expect(find.text('Vybrat vše'), findsOneWidget);
      expect(find.text('Hotovo'), findsOneWidget);
      expect(find.text('Exportovat balíček (0)'), findsOneWidget);

      // Tap on first session to select
      await tester.tap(find.text('Automotodrom Brno - Stint 1'));
      await tester.pumpAndSettle();

      expect(find.text('Vybráno: 1'), findsOneWidget);
      expect(find.text('Exportovat balíček (1)'), findsOneWidget);

      // Tap "Vybrat vše" to select both
      await tester.tap(find.text('Vybrat vše'));
      await tester.pumpAndSettle();

      expect(find.text('Vybráno: 2'), findsOneWidget);
      expect(find.text('Exportovat balíček (2)'), findsOneWidget);
      expect(find.text('Odznačit'), findsOneWidget);

      // Tap "Hotovo" to exit selection mode
      await tester.tap(find.text('Hotovo'));
      await tester.pumpAndSettle();

      expect(find.text('Historie'), findsOneWidget);
      expect(find.byTooltip('Vybrat jízdy'), findsOneWidget);
      expect(find.text('Exportovat balíček'), findsNothing);
    });
  });
}
