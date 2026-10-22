import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/ui/widgets/apple_scale_button.dart';
import 'package:motologger/ui/widgets/apple_modal_sheet.dart';

void main() {
  group('AppleScaleButton Widget Tests', () {
    testWidgets('Renders child and invokes onPressed on tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppleScaleButton(
                onPressed: () => tapped = true,
                child: const Text('Apple Button'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Apple Button'), findsOneWidget);
      await tester.tap(find.text('Apple Button'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Applies scale transformation on press down and rebounds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppleScaleButton(
                onPressed: () {},
                pressedScale: 0.95,
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(AppleScaleButton));
      final gesture = await tester.createGesture();
      await gesture.down(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final scaleFinder = find.descendant(
        of: find.byType(AppleScaleButton),
        matching: find.byType(ScaleTransition),
      );
      expect(scaleFinder, findsOneWidget);
      final scaleWidget = tester.widget<ScaleTransition>(scaleFinder);
      expect(scaleWidget.scale.value, lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();

      final reboundWidget = tester.widget<ScaleTransition>(scaleFinder);
      expect(reboundWidget.scale.value, closeTo(1.0, 0.001));
    });

    testWidgets('Bypasses scale when reduce motion is enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: AppleScaleButton(
                  onPressed: () {},
                  child: const Text('Static Scale'),
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.text('Static Scale'));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // With reduce motion, no ScaleTransition is used
      expect(
        find.descendant(of: find.byType(AppleScaleButton), matching: find.byType(ScaleTransition)),
        findsNothing,
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('AppleModalSheet Widget Tests', () {
    testWidgets('Renders grabber pill, title, subtitle, and action items', (tester) async {
      bool actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppleModalSheet<void>(
                    context: context,
                    title: 'Možnosti nastavení',
                    subtitle: 'Podrobný popis akcí',
                    actions: [
                      AppleSheetAction(
                        icon: CupertinoIcons.gear,
                        title: 'Spustit akci',
                        subtitle: 'Doplňující text',
                        onPressed: () => actionTapped = true,
                      ),
                      AppleSheetAction(
                        icon: CupertinoIcons.delete,
                        title: 'Smazat položku',
                        isDestructive: true,
                        onPressed: () {},
                      ),
                    ],
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Možnosti nastavení'), findsOneWidget);
      expect(find.text('Podrobný popis akcí'), findsOneWidget);
      expect(find.text('Spustit akci'), findsOneWidget);
      expect(find.text('Smazat položku'), findsOneWidget);
      expect(find.text('Zrušit'), findsOneWidget);

      await tester.tap(find.text('Spustit akci'));
      await tester.pumpAndSettle();

      expect(actionTapped, isTrue);
      // Sheet should be dismissed
      expect(find.text('Možnosti nastavení'), findsNothing);
    });

    testWidgets('Cancel button dismisses the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppleModalSheet<void>(
                    context: context,
                    title: 'Test Sheet',
                    actions: [
                      AppleSheetAction(
                        title: 'Action 1',
                        onPressed: () {},
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Test Sheet'), findsOneWidget);
      await tester.tap(find.text('Zrušit'));
      await tester.pumpAndSettle();

      expect(find.text('Test Sheet'), findsNothing);
    });
  });
}
