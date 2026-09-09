import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/ui/widgets/motorcycle_tank_illustration.dart';
import 'package:motologger/ui/widgets/apple_spirit_level.dart';

void main() {
  testWidgets('MotorcycleTankIllustration renders correctly and displays angle badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MotorcycleTankIllustration(
            leanAngleDeg: -12.4,
            isCalibrated: false,
            isStable: true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MotorcycleTankIllustration), findsOneWidget);
    expect(find.textContaining('12.4°'), findsOneWidget);
    expect(find.text('PŘIPRAVENO'), findsOneWidget);
  });

  testWidgets('AppleSpiritLevelWidget renders simulated roll angle and stability', (WidgetTester tester) async {
    double? capturedAngle;
    bool? capturedStability;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppleSpiritLevelWidget(
            simulatedRollDeg: -12.4,
            onAngleChanged: (angle) => capturedAngle = angle,
            onStabilityChanged: (stable) => capturedStability = stable,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppleSpiritLevelWidget), findsOneWidget);
    expect(find.text('12.4°'), findsOneWidget);
    expect(find.text('VLEVO (STOJÁNEK)'), findsOneWidget);
    expect(capturedAngle, -12.4);
    expect(capturedStability, true);
  });

  test('Mounting offset calculation math verification', () {
    // Motorcycle resting on left side stand at -12.4°
    const phoneRoll = -12.4;
    // Sensor mounted slightly tilted under seat reading -10.1°
    const rawEsp = -10.1;
    // Calculated mounting offset = rawEsp - phoneRoll
    const offset = rawEsp - phoneRoll; // -10.1 - (-12.4) = +2.3°
    expect((offset - 2.3).abs() < 0.001, true);

    // When motorcycle is upright (true 0.0°):
    // rawEsp reads +2.3°
    // Calibrated roll = rawEsp - offset = +2.3° - (+2.3°) = 0.0°
    const uprightRaw = 2.3;
    const calibratedUpright = uprightRaw - offset;
    expect(calibratedUpright.abs() < 0.001, true);
  });
}
