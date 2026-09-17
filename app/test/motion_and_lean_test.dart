import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/main.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/widgets/apple_tab_bar.dart';
import 'package:motologger/ui/widgets/corner_gradient_breather.dart';
import 'liquid_glass_test.dart' show ReviewDatabase, capture, loadReviewFonts;

class LeanReviewManager extends TelemetryManager {
  LeanReviewManager(ReviewDatabase db)
      : super(
            bleService: BleService(), gpsService: GpsService(), dbService: db);
  double angle = -10;
  bool available = true;
  @override
  bool get isSimulationMode => available;
  @override
  TelemetryPacket get latestPacket =>
      super.latestPacket.copyWith(leanAngleDeg: angle);
  void update(double value, {bool connected = true}) {
    angle = value;
    available = connected;
    notifyListeners();
  }
}

void main() {
  setUpAll(loadReviewFonts);

  testWidgets(
      'selection slides, can reverse mid-flight, respects reduced motion',
      (tester) async {
    var index = 0;
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
                width: 360,
                child: AppleTabBar(
                    currentIndex: index,
                    onTabSelected: (value) => setState(() => index = value)))),
      );
    })));
    final selection = find.byKey(const ValueKey('tab-selection'));
    final start = tester.getCenter(selection).dx;
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final intermediate = tester.getCenter(selection).dx;
    expect(intermediate, greaterThan(start));
    await tester.pump(const Duration(milliseconds: 300));
    final end = tester.getCenter(selection).dx;
    expect(intermediate, lessThan(end));
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final reversing = tester.getCenter(selection).dx;
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump();
    expect(tester.getCenter(selection).dx, closeTo(reversing, .01));
    await tester.pumpAndSettle();
    update(() => reduced = true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(selection).dx, closeTo(start, .01));
  });

  test('lean palette progresses from mild green to orange and full red', () {
    expect(LeanEdgePainter.colorFor(10), LeanEdgePainter.green);
    expect(LeanEdgePainter.colorFor(-30), LeanEdgePainter.orange);
    expect(LeanEdgePainter.colorFor(45), LeanEdgePainter.red);
    expect(LeanEdgePainter.colorFor(90), LeanEdgePainter.red);
  });

  testWidgets('lean direction, disconnect, invalid data and opaque fallback',
      (tester) async {
    var angle = -12.0;
    var enabled = true;
    var opaque = false;
    late StateSetter update;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: opaque),
          child: CornerGradientBreather(leanAngleDeg: angle, enabled: enabled));
    })));
    LeanEdgePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<LeanEdgePainter>()
        .single;
    expect(painter().angle, -12);
    update(() => angle = 45);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(painter().angle, inExclusiveRange(-12, 45));
    await tester.pumpAndSettle();
    expect(painter().angle, 45);
    update(() => enabled = false);
    await tester.pump();
    expect(painter().angle, 0);
    update(() {
      enabled = true;
      angle = double.nan;
    });
    await tester.pumpAndSettle();
    expect(painter().angle, 0);
    update(() {
      angle = -30;
      opaque = true;
    });
    await tester.pumpAndSettle();
    expect(painter().opaque, isTrue);
  });

  testWidgets('render lean feedback on actual ride screen and retain tab state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = ReviewDatabase();
    final manager = LeanReviewManager(db);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MotoLoggerApp(telemetryManager: manager, dbService: db)));
    await tester.pumpAndSettle();
    await capture(tester, key, 'lean-left-green');
    manager.update(-30);
    await tester.pumpAndSettle();
    await capture(tester, key, 'lean-left-orange');
    manager.update(45);
    await tester.pumpAndSettle();
    await capture(tester, key, 'lean-right-red');
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    await capture(tester, key, 'tab-slide-midpoint');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await tester.pumpAndSettle();
    expect(find.text('45°'), findsWidgets);
    manager.update(45, connected: false);
    await tester.pumpAndSettle();
    await capture(tester, key, 'lean-disconnected');
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    manager.update(-30);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zahájit jízdu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pozastavit jízdu'));
    await tester.pumpAndSettle();
    expect(manager.isPaused, isTrue);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
    manager.bleService.dispose();
    manager.gpsService.dispose();
  });
}
