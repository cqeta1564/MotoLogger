import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/main.dart';
import 'package:motologger/core/theme/app_theme.dart';
import 'package:motologger/core/preferences/app_preferences.dart';
import 'package:motologger/models/can_profile.dart';
import 'package:motologger/models/fused_sample.dart';
import 'package:motologger/models/session.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/widgets/glass_surface.dart';
import 'package:motologger/ui/settings/import_bike_profile_screen.dart';
import 'package:motologger/services/can_profile_service.dart';

class ReviewDatabase extends DatabaseService {
  ReviewDatabase() : super.forTesting();
  final settings = <String, String>{};
  final sessions = <RideSession>[];
  final samples = <FusedSample>[];
  bool failSave = false;
  bool failStart = false;
  bool failSamples = false;
  @override
  Future<String?> getSetting(String key) async => settings[key];
  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<BikeProfile>> getAllBikeProfiles() async => [];
  @override
  Future<List<RideSession>> getAllSessions() async =>
      sessions.reversed.toList();
  @override
  Future<int> startSession(String title) async {
    if (failStart) throw const FileSystemException('Full disk');
    final id = sessions.length + 1;
    sessions.add(
        RideSession(id: id, title: title, startTime: DateTime(2026, 9, 17, 9)));
    return id;
  }

  @override
  Future<void> updateSession(RideSession session) async {
    if (failSave) throw const FileSystemException('Full disk');
    sessions[sessions.indexWhere((item) => item.id == session.id)] = session;
  }

  @override
  Future<void> insertSampleBatch(List<FusedSample> batch) async {
    if (failSamples) throw const FileSystemException('Full disk');
    samples.addAll(batch);
  }

  @override
  Future<List<FusedSample>> getSamplesForSession(int id) async =>
      samples.where((s) => s.sessionId == id).toList();
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
  final previous = debugDisableShadows;
  try {
    debugDisableShadows = false;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    repaint(key.currentContext!.findRenderObject()!);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../docs/review/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = previous;
    key.currentContext!.findRenderObject()!.markNeedsPaint();
    await tester.pump();
  }
}

Future<void> loadReviewFonts() async {
  if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
  for (final entry in {
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'packages/cupertino_icons/CupertinoIcons':
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final file =
      File('$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  if (file.existsSync()) {
    for (final family in [
      'Ahem',
      'monospace',
      'Roboto',
      '-apple-system',
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay'
    ]) {
      await (FontLoader(family)
            ..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync()))))
          .load();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadReviewFonts();
  });

  testWidgets('ride, save retry, navigation and saved history survive remount',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = ReviewDatabase();
    final ble = BleService();
    final gps = GpsService();
    final manager =
        TelemetryManager(bleService: ble, gpsService: gps, dbService: db);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MotoLoggerApp(telemetryManager: manager, dbService: db)));
    await tester.pump(const Duration(milliseconds: 200));
    await capture(tester, key, 'after-ride-disconnected');
    await tester.tap(find.text('Vyzkoušet demo'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Demo jízda'), findsOneWidget);
    db.failStart = true;
    await tester.tap(find.text('Zahájit jízdu'));
    await tester.pump();
    expect(manager.isRecording, isFalse);
    expect(find.textContaining('Záznam se nepodařilo'), findsOneWidget);
    db.failStart = false;
    await tester.tap(find.text('Zahájit jízdu'));
    await tester.pump(const Duration(seconds: 1));
    expect(manager.isRecording, isTrue);
    await capture(tester, key, 'after-ride-recording');
    await tester.tap(find.text('Pozastavit jízdu'));
    await tester.pump();
    expect(manager.isPaused, isTrue);
    db.failSave = true;
    await tester.tap(find.text('Uložit jízdu'));
    await tester.pump();
    expect(manager.isRecording, isTrue);
    expect(find.textContaining('Jízdu se nepodařilo uložit'), findsOneWidget);
    await capture(tester, key, 'after-save-error');
    db.failSave = false;
    await tester.tap(find.text('Uložit jízdu'));
    await tester.pump();
    expect(manager.isRecording, isFalse);
    expect(db.sessions.single.title, startsWith('Demo'));
    expect(db.samples, isNotEmpty);
    manager.setSimulationMode(false);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(db.sessions.single.title), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Jízda je uložena v telefonu.'), findsNothing);
    await capture(tester, key, 'after-history');
    await tester.tap(find.text(db.sessions.single.title));
    await tester.pumpAndSettle();
    await capture(tester, key, 'after-detail');
    await tester.tap(find.byTooltip('Zpět'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    await capture(tester, key, 'after-settings');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester
        .pumpWidget(MotoLoggerApp(telemetryManager: manager, dbService: db));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    expect(find.text(db.sessions.single.title), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    ble.dispose();
    gps.dispose();
  });

  testWidgets(
      'small phone, enlarged type and landscape keep primary action reachable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = ReviewDatabase();
    final ble = BleService();
    final gps = GpsService();
    final manager =
        TelemetryManager(bleService: ble, gpsService: gps, dbService: db);
    final key = GlobalKey();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final size in [
      const Size(320, 568),
      const Size(430, 932),
      const Size(844, 390)
    ]) {
      tester.view.physicalSize = size;
      tester.platformDispatcher.platformBrightnessTestValue =
          size.width == 430 ? Brightness.dark : Brightness.light;
      tester.platformDispatcher.textScaleFactorTestValue =
          size.width == 430 ? 1.8 : 1;
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MotoLoggerApp(telemetryManager: manager, dbService: db)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Vyzkoušet demo').hitTestable(), findsOneWidget);
      expect(Theme.of(tester.element(find.text('Vyzkoušet demo'))).brightness,
          Brightness.light);
      expect(tester.takeException(), isNull);
      await capture(
          tester, key, 'after-${size.width.round()}x${size.height.round()}');
    }
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    ble.dispose();
    gps.dispose();
  });

  testWidgets(
      'concurrent starts and failed sample writes preserve one complete ride',
      (tester) async {
    final db = ReviewDatabase();
    final ble = BleService();
    final gps = GpsService();
    final manager =
        TelemetryManager(bleService: ble, gpsService: gps, dbService: db);
    manager.setSimulationMode(true);
    await Future.wait([
      manager.startRecording('Demo regression'),
      manager.startRecording('Duplicate')
    ]);
    expect(db.sessions.length, 1);
    await tester.pump(const Duration(milliseconds: 200));
    manager.pauseRecording();
    final count = manager.sampleCount;
    expect(count, greaterThan(0));
    db.failSamples = true;
    await expectLater(
        manager.stopRecording(), throwsA(isA<FileSystemException>()));
    expect(manager.isRecording, isTrue);
    expect(manager.isPaused, isTrue);
    db.failSamples = false;
    await manager.stopRecording();
    expect(db.samples.length, count);
    expect(db.sessions.single.sampleCount, count);
    expect(manager.isRecording, isFalse);
    manager.dispose();
    ble.dispose();
    gps.dispose();
    await tester.pump();
  });

  testWidgets(
      'profile input survives validation, keyboard and cancelled dismissal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final profileService = CanProfileService(dbService: ReviewDatabase());
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => ImportBikeProfileScreen(
                                  canProfileService: profileService))),
                      child: const Text('Open profile'))),
            ))));
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '{invalid profile');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.text('{invalid profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'after-profile-keyboard-large-text');
    await tester.tap(find.byTooltip('Zpět'));
    await tester.pumpAndSettle();
    expect(find.text('Zahodit rozepsaný profil?'), findsOneWidget);
    await tester.tap(find.text('Pokračovat v úpravě'));
    await tester.pumpAndSettle();
    expect(find.text('{invalid profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Zpět'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zahodit'));
    await tester.pumpAndSettle();
    expect(find.text('Open profile'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    profileService.dispose();
  });

  testWidgets(
      'opaque material preference persists and high contrast removes filters',
      (tester) async {
    final db = ReviewDatabase();
    final preferences = AppPreferences(db);
    await preferences.setReduceTransparency(true);
    final restored = AppPreferences(db);
    await restored.load();
    expect(restored.reduceTransparency, isTrue);
    await tester.pumpWidget(AppPreferencesScope(
        preferences: restored,
        child: const MaterialApp(
            home: Scaffold(
                body: GlassSurface(child: Text('Readable controls'))))));
    expect(find.byType(BackdropFilter), findsNothing);
    await restored.setReduceTransparency(false);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(highContrast: true),
            child: GlassSurface(child: Text('Readable controls')))));
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
    restored.dispose();
  });
}
