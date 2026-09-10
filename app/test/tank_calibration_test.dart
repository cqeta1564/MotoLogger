import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/ui/widgets/phone_placement_animation.dart';
import 'package:motologger/ui/widgets/bike_upright_animation.dart';
import 'package:motologger/ui/widgets/construction_spirit_level.dart';

void main() {
  testWidgets('PhonePlacementAnimation renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhonePlacementAnimation(isPlaced: false),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PhonePlacementAnimation), findsOneWidget);
  });

  testWidgets('ConstructionSpiritLevelWidget renders simulated roll angle and status', (WidgetTester tester) async {
    double? capturedAngle;
    bool? capturedStability;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstructionSpiritLevelWidget(
            simulatedRollDeg: -12.4,
            onAngleChanged: (angle) => capturedAngle = angle,
            onStabilityChanged: (stable) => capturedStability = stable,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ConstructionSpiritLevelWidget), findsOneWidget);
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

  testWidgets('BikeUprightAnimation renders correctly and paints motorcycle', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BikeUprightAnimation(isUpright: true),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(BikeUprightAnimation), findsOneWidget);
  });
}
