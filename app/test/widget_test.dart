import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/ui/widgets/gg_friction_reticle.dart';
import 'package:motologger/ui/widgets/slide_to_unlock.dart';

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
}
