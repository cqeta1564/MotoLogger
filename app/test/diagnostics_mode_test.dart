import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/core/constants/ble_constants.dart';
import 'package:motologger/core/theme/app_theme.dart';
import 'package:motologger/models/can_profile.dart';
import 'package:motologger/models/dtc_code.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/settings/diagnostics_screen.dart';

class _TestDatabase extends DatabaseService {
  _TestDatabase() : super.forTesting();
  final Map<String, String> settings = {};
  final List<RideSession> sessions = [];
  final List<FusedSample> samples = [];

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<BikeProfile>> getAllBikeProfiles() async => [];

  @override
  Future<List<RideSession>> getAllSessions() async => sessions;

  @override
  Future<int> startSession(String title) async {
    final id = sessions.length + 1;
    sessions.add(
      RideSession(id: id, title: title, startTime: DateTime(2026, 10, 17, 12)),
    );
    return id;
  }

  @override
  Future<void> updateSession(RideSession session) async {
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) sessions[idx] = session;
  }

  @override
  Future<void> insertSampleBatch(List<FusedSample> batch) async {
    samples.addAll(batch);
  }
}

void main() {
  group('DiagnosticTroubleCode model & SAE J2012 parser', () {
    test('parses stored and pending DTC tokens with deduplication and Czech labels', () {
      final codes = DiagnosticTroubleCode.parseList('P0122:S;C0035:P;P0122:S;U0100:S');
      expect(codes.length, 3);

      expect(codes[0].code, 'P0122');
      expect(codes[0].isPending, isFalse);
      expect(codes[0].statusLabelCz, 'Uložená (Mode 03)');
      expect(codes[0].systemCategoryCz, 'Motor a řízení (Powertrain)');
      expect(codes[0].descriptionCz, contains('škrticí klapky (TPS)'));

      expect(codes[1].code, 'C0035');
      expect(codes[1].isPending, isTrue);
      expect(codes[1].statusLabelCz, 'Čekající (Mode 07)');
      expect(codes[1].systemCategoryCz, 'Podvozek a ABS (Chassis)');

      expect(codes[2].code, 'U0100');
      expect(codes[2].systemCategoryCz, 'Sběrnice CAN (Network)');
    });

    test('returns empty list for empty payload', () {
      expect(DiagnosticTroubleCode.parseList(''), isEmpty);
      expect(DiagnosticTroubleCode.parseList('   '), isEmpty);
    });
  });

  group('TelemetryManager Diagnostic Mode & Safety Interlocks', () {
    late _TestDatabase db;
    late BleService ble;
    late GpsService gps;
    late TelemetryManager manager;

    setUp(() {
      db = _TestDatabase();
      ble = BleService();
      gps = GpsService();
      manager = TelemetryManager(
        bleService: ble,
        gpsService: gps,
        dbService: db,
      );
    });

    tearDown(() {
      manager.dispose();
      ble.dispose();
      gps.dispose();
    });

    test('remains in passive Listen-Only mode by default and enables active CAN TX only in Diagnostic Mode', () async {
      manager.setSimulationMode(true);
      expect(manager.isDiagnosticModeActive, isFalse);

      final enabled = await manager.setDiagnosticMode(true);
      expect(enabled, isTrue);
      expect(manager.isDiagnosticModeActive, isTrue);

      final dtcs = await manager.scanDiagnosticTroubleCodes();
      expect(dtcs.length, 2);
      expect(dtcs.first.code, 'P0122');

      final cleared = await manager.clearDiagnosticTroubleCodes();
      expect(cleared, isTrue);
      expect(manager.diagnosticTroubleCodes, isEmpty);

      await manager.setDiagnosticMode(false);
      expect(manager.isDiagnosticModeActive, isFalse);
    });

    test('automatically disables Diagnostic Mode when speed exceeds 5 km/h', () async {
      manager.setSimulationMode(true);
      await manager.setDiagnosticMode(true);
      expect(manager.isDiagnosticModeActive, isTrue);

      // Emit a packet simulating the motorcycle starting to move (12 km/h > 5 km/h)
      ble.emitMockTelemetryPacket(
        TelemetryPacket.initial().copyWith(
          vehicleSpeedKmh: 12,
          engineRpm: 2800,
          statusFlags: 0x1F,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(manager.isDiagnosticModeActive, isFalse);
      expect(manager.diagnosticStatusMessage, contains('> 5 km/h'));
    });

    test('automatically disables Diagnostic Mode when ride recording starts', () async {
      manager.setSimulationMode(true);
      await manager.setDiagnosticMode(true);
      expect(manager.isDiagnosticModeActive, isTrue);

      await manager.startRecording('Test Ride');
      expect(manager.isRecording, isTrue);
      expect(manager.isDiagnosticModeActive, isFalse);

      // Attempting to enable diagnostic mode during recording must be rejected
      final denied = await manager.setDiagnosticMode(true);
      expect(denied, isFalse);
      expect(manager.isDiagnosticModeActive, isFalse);

      await manager.stopRecording();
    });

    test('BleConstants diagnostic opcodes match firmware protocol', () {
      expect(BleConstants.cmdDiagSetMode, 0x30);
      expect(BleConstants.cmdDiagReadDtc, 0x31);
      expect(BleConstants.cmdDiagClearDtc, 0x32);
      expect(BleConstants.respDiagMode, 0xB0);
      expect(BleConstants.respDiagDtcList, 0xB1);
      expect(BleConstants.respDiagClearAck, 0xB2);

      // Verify TelemetryPacket bit 4 status flag decoding
      final pktPassive = TelemetryPacket.initial().copyWith(statusFlags: 0x0F);
      final pktActive = TelemetryPacket.initial().copyWith(statusFlags: 0x1F);
      expect(pktPassive.isDiagnosticModeActive, isFalse);
      expect(pktActive.isDiagnosticModeActive, isTrue);

      // Verify BleService response handler does not throw on diagnostic packets
      final rawDtcPayload = utf8.encode('P0115:S;C0035:P');
      ble.handleCommandResponseForTest([BleConstants.respDiagMode, 1]);
      ble.handleCommandResponseForTest([
        BleConstants.respDiagDtcList,
        2,
        ...rawDtcPayload,
      ]);
      ble.handleCommandResponseForTest([BleConstants.respDiagClearAck, 1]);
    });
  });

  testWidgets('DiagnosticsScreen activates OBD-II TX on enter, scans/clears DTCs, and returns to Listen-Only on exit', (tester) async {
    final db = _TestDatabase();
    final ble = BleService();
    final gps = GpsService();
    final manager = TelemetryManager(
      bleService: ble,
      gpsService: gps,
      dbService: db,
    );

    manager.setSimulationMode(true);
    expect(manager.isDiagnosticModeActive, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DiagnosticsScreen(telemetryManager: manager),
                    ),
                  );
                },
                child: const Text('Otevřít diagnostiku'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Otevřít diagnostiku'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Diagnostic Mode was automatically activated and DTCs were scanned
    expect(manager.isDiagnosticModeActive, isTrue);
    expect(find.text('Aktivní diagnostika (Vysílání OBD-II)'), findsOneWidget);
    expect(find.text('P0122'), findsOneWidget);
    expect(find.text('C0035'), findsOneWidget);

    // Clear DTCs via confirmation dialog
    await tester.ensureVisible(find.text('Smazat chybové kódy (ECU Reset)'));
    await tester.pump();
    await tester.tap(find.text('Smazat chybové kódy (ECU Reset)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Smazat paměť závad ECU?'), findsOneWidget);
    await tester.tap(find.text('Smazat závady'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(manager.diagnosticTroubleCodes, isEmpty);
    expect(find.text('Paměť závad je čistá', skipOffstage: false), findsOneWidget);

    // Pop DiagnosticsScreen and verify ESP32-S3 is returned to Listen-Only passive mode
    await tester.tap(find.byTooltip('Zpět'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(manager.isDiagnosticModeActive, isFalse);

    // Unmount widget tree and dispose services before testWidgets checks pending timers
    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
    ble.dispose();
    gps.dispose();
  });
}
