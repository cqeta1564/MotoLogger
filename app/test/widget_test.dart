import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/telemetry_packet.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/dashboard/dashboard_screen.dart';
import 'package:motologger/ui/widgets/gg_friction_reticle.dart';
import 'package:motologger/ui/widgets/slide_to_unlock.dart';
import 'liquid_glass_test.dart' show ReviewDatabase;

class _GearTestManager extends TelemetryManager {
  int gearValue = -1;
  _GearTestManager()
      : super(
          bleService: BleService(),
          gpsService: GpsService(),
          dbService: ReviewDatabase(),
        );

  @override
  bool get isSimulationMode => true;

  @override
  TelemetryPacket get latestPacket =>
      super.latestPacket.copyWith(gear: gearValue, vehicleSpeedKmh: 45);
}

void main() {
  testWidgets('GgFrictionReticle renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GgFrictionReticle(
            accelXG: 0.2,
            accelYG: 0.4,
            frictionEnvelope: [0.5, 0.6, 0.7],
            size: 200,
          ),
        ),
      ),
    );

    expect(find.byType(GgFrictionReticle), findsOneWidget);
  });

  testWidgets('SlideToUnlock displays unlock label', (WidgetTester tester) async {
    bool unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideToUnlock(
            onUnlocked: () => unlocked = true,
            label: 'PŘEJETÍM ODEMKNOUT ➔',
          ),
        ),
      ),
    );

    expect(find.text('PŘEJETÍM ODEMKNOUT ➔'), findsOneWidget);
    expect(unlocked, isFalse);
  });

  testWidgets('DashboardScreen displays em-dash for unknown gear (-1) and N for neutral (0)', (WidgetTester tester) async {
    final manager = _GearTestManager();
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(telemetryManager: manager),
      ),
    );
    await tester.pump();

    expect(find.text('-1'), findsNothing);
    expect(find.text('—'), findsWidgets);

    manager.gearValue = 0;
    manager.notifyListeners();
    await tester.pump();
    expect(find.text('N'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    manager.bleService.dispose();
    manager.gpsService.dispose();
  });
}
