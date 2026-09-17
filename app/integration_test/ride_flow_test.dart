import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:motologger/main.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/settings/settings_screen.dart';

/// Run on an emulator/test device only: creates a labeled demo ride in its local DB.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
      'native demo recording, SQLite persistence, navigation and material',
      (tester) async {
    final db = DatabaseService.instance;
    final ble = BleService();
    final gps = GpsService();
    final manager =
        TelemetryManager(bleService: ble, gpsService: gps, dbService: db);
    final directory = await getApplicationDocumentsDirectory();
    Future<void> screenshot(String name) async {
      // Let native I/O, transitions and the test pointer overlay settle.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final bytes = await binding.takeScreenshot(name);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
    }

    await tester
        .pumpWidget(MotoLoggerApp(telemetryManager: manager, dbService: db));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await screenshot('android-ride-disconnected');
    await tester.tap(find.text('Vyzkoušet demo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Zahájit jízdu'));
    await tester.pump(const Duration(seconds: 2));
    expect(manager.isRecording, isTrue);
    final frames = <FrameTiming>[];
    void collectFrames(List<FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(collectFrames);
    try {
      await tester.pump(const Duration(seconds: 3));
      await tester.drag(find.byKey(const PageStorageKey('ride-scroll')),
          const Offset(0, -180));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byKey(const PageStorageKey('ride-scroll')),
          const Offset(0, 180));
      await tester.pump(const Duration(milliseconds: 500));
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(collectFrames);
    }
    binding.reportData ??= {};
    binding.reportData!['ride_frame_timings'] = {
      'method':
          'SchedulerBinding FrameTiming; debug build, Android emulator, Skia',
      'frames': frames.length,
      'build_us':
          frames.map((frame) => frame.buildDuration.inMicroseconds).toList(),
      'raster_us':
          frames.map((frame) => frame.rasterDuration.inMicroseconds).toList(),
    };
    await screenshot('android-ride-recording');
    await tester.tap(find.text('Pozastavit jízdu'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(manager.isPaused, isTrue);
    await screenshot('android-ride-paused');
    await tester.tap(find.text('Pokračovat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(manager.isPaused, isFalse);
    await tester.tap(find.text('Pozastavit jízdu'));
    await tester.pump();
    await tester.tap(find.text('Uložit jízdu'));
    await tester.pump(const Duration(seconds: 1));
    expect(manager.isRecording, isFalse);
    manager.setSimulationMode(false);
    final sessions = await db.getAllSessions();
    final saved = sessions.first;
    expect(saved.title, startsWith('Demo'));
    expect(saved.sampleCount, greaterThan(0));
    expect(await db.getSamplesForSession(saved.id!), isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    await screenshot('android-history');
    await tester.scrollUntilVisible(find.text(saved.title).first, 160,
        scrollable: find
            .descendant(
                of: find.byKey(const PageStorageKey('history-scroll')),
                matching: find.byType(Scrollable))
            .first);
    await Scrollable.ensureVisible(tester.element(find.text(saved.title).first),
        alignment: 0.35);
    await tester.pumpAndSettle();
    await tester.tap(find.text(saved.title).first);
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 50 && find.text('Náklon vlevo').evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Náklon vlevo'), findsOneWidget);
    await screenshot('android-detail');
    await tester.tap(find.byTooltip('Zpět'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    await screenshot('android-settings');
    await tester.scrollUntilVisible(find.text('Omezit průhlednost'), 160,
        scrollable: find
            .descendant(
                of: find.byKey(const PageStorageKey('settings-scroll')),
                matching: find.byType(Scrollable))
            .first);
    final preferenceRow = find.ancestor(
        of: find.text('Omezit průhlednost'),
        matching: find.byType(SettingsRow));
    await Scrollable.ensureVisible(tester.element(preferenceRow), alignment: 0.5);
    await tester.pumpAndSettle();
    final toggle = find.descendant(
        of: preferenceRow, matching: find.byType(CupertinoSwitch));
    if (!tester.widget<CupertinoSwitch>(toggle).value) {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    expect(await db.getSetting('reduce_transparency'), 'true');
    await screenshot('android-opaque');
    await File('${directory.path}/performance.json')
        .writeAsString(jsonEncode(binding.reportData!['ride_frame_timings']));
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    ble.dispose();
    gps.dispose();
    // Recreate services while preserving the actual SQLite records. OS relaunch is checked separately.
    final freshBle = BleService();
    final freshGps = GpsService();
    final fresh = TelemetryManager(
        bleService: freshBle, gpsService: freshGps, dbService: db);
    await tester
        .pumpWidget(MotoLoggerApp(telemetryManager: fresh, dbService: db));
    await tester.pumpAndSettle();
    expect(await db.getSetting('reduce_transparency'), 'true');
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    expect(
        (await db.getAllSessions()).any((ride) => ride.id == saved.id), isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
    fresh.dispose();
    freshBle.dispose();
    freshGps.dispose();
  });
}
