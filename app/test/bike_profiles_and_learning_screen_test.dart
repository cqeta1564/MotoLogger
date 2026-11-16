import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/core/theme/app_theme.dart';
import 'package:motologger/models/can_profile.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/can_profile_service.dart';
import 'package:motologger/services/database_service.dart';
import 'package:motologger/services/gps_service.dart';
import 'package:motologger/services/telemetry_manager.dart';
import 'package:motologger/ui/settings/bike_learning_screen.dart';
import 'package:motologger/ui/settings/bike_profiles_screen.dart';
import 'package:motologger/ui/settings/import_bike_profile_screen.dart';

class _FakeProfileDatabaseService extends DatabaseService {
  _FakeProfileDatabaseService() : super.forTesting();

  final Map<String, String> settings = {};
  final List<BikeProfile> profiles = [];

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<BikeProfile>> getAllBikeProfiles() async =>
      List<BikeProfile>.from(profiles);

  @override
  Future<void> saveBikeProfile(BikeProfile profile) async {
    profiles.removeWhere((p) => p.id == profile.id);
    profiles.add(profile);
  }

  @override
  Future<void> deleteBikeProfile(String id) async {
    profiles.removeWhere((p) => p.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': ''};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('BikeProfilesScreen Widget Tests', () {
    testWidgets(
      'Renders default OBD-II profile and empty state when no custom profiles exist',
      (tester) async {
        final db = _FakeProfileDatabaseService();
        final profileService = CanProfileService(dbService: db);
        await profileService.loadProfiles();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: BikeProfilesScreen(canProfileService: profileService),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Profily motocyklů'), findsOneWidget);
        expect(find.text('Standardní OBD-II'), findsOneWidget);
        expect(
          find.text('Zatím nemáte naučenou žádnou motorku'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Switches active profile and deletes saved custom profile after confirmation',
      (tester) async {
        final db = _FakeProfileDatabaseService();
        final customProfile = BikeProfile(
          id: 'yamaha_r6',
          name: 'Yamaha YZF-R6',
          createdAt: DateTime.utc(2026, 5, 1),
          canBaudrate: 500000,
          signals: const {
            'engine_rpm': CanSignalMapping(
              key: 'engine_rpm',
              canId: '0x1F0',
              startByte: 0,
              lengthBytes: 2,
              unit: 'RPM',
            ),
            'vehicle_speed': CanSignalMapping(
              key: 'vehicle_speed',
              canId: '0x1F0',
              startByte: 2,
              lengthBytes: 2,
              multiplier: 0.05,
              unit: 'km/h',
            ),
          },
        );
        await db.saveBikeProfile(customProfile);

        final profileService = CanProfileService(dbService: db);
        await profileService.loadProfiles();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: BikeProfilesScreen(canProfileService: profileService),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Yamaha YZF-R6'), findsOneWidget);
        expect(find.text('2 mapovaných signálů | 500 kbps'), findsOneWidget);
        expect(profileService.activeProfile.id, equals('standard_obd2'));

        // Activate custom profile by tapping its card
        await tester.tap(find.text('Yamaha YZF-R6'));
        await tester.pumpAndSettle();
        expect(profileService.activeProfile.id, equals('yamaha_r6'));

        // Switch back to Standard OBD-II so the delete button is visible on custom profile
        await tester.tap(find.text('Standardní OBD-II'));
        await tester.pumpAndSettle();
        expect(profileService.activeProfile.id, equals('standard_obd2'));

        // Tap trash icon to delete custom profile
        final trashFinder = find.byIcon(CupertinoIcons.trash);
        expect(trashFinder, findsOneWidget);
        await tester.tap(trashFinder);
        await tester.pumpAndSettle();

        // Confirm deletion in CupertinoAlertDialog
        expect(find.text('Smazat profil "Yamaha YZF-R6"?'), findsOneWidget);
        await tester.tap(find.text('Smazat'));
        await tester.pumpAndSettle();

        expect(find.text('Yamaha YZF-R6'), findsNothing);
        expect(
          find.text('Zatím nemáte naučenou žádnou motorku'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Navigates to ImportBikeProfileScreen when Přidat is tapped', (
      tester,
    ) async {
      final db = _FakeProfileDatabaseService();
      final profileService = CanProfileService(dbService: db);
      await profileService.loadProfiles();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BikeProfilesScreen(canProfileService: profileService),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Přidat'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportBikeProfileScreen), findsOneWidget);
    });
  });

  group('BikeLearningScreen Widget Tests', () {
    testWidgets(
      'Enforces 54 px height and 14 px radius on main action buttons across all learning steps',
      (tester) async {
        final db = _FakeProfileDatabaseService();
        final bleService = BleService();
        final gpsService = GpsService();
        final telemetryManager = TelemetryManager(
          bleService: bleService,
          gpsService: gpsService,
          dbService: db,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: BikeLearningScreen(telemetryManager: telemetryManager),
          ),
        );
        await tester.pump();

        // Step 0: Preparation View
        expect(find.text('Naučit se motorku'), findsOneWidget);
        expect(
          find.text('Automatické mapování CAN sběrnice'),
          findsOneWidget,
        );
        expect(find.text('Volnoběh (~10 sekund)'), findsOneWidget);
        expect(find.text('Túrování na místě (~10 sekund)'), findsOneWidget);
        expect(
          find.text('Krátká jízda s řazením (~30 sekund)'),
          findsOneWidget,
        );

        // Verify MicroSD import button height (54 px) and border radius (14 px)
        final sdButtonTextFinder = find.text('Importovat z MicroSD karty');
        expect(sdButtonTextFinder, findsOneWidget);
        final sdSizedBoxFinder = find
            .ancestor(
              of: sdButtonTextFinder,
              matching: find.byWidgetPredicate(
                (w) => w is SizedBox && w.height == AppTheme.primaryButtonHeight,
              ),
            )
            .first;
        expect(
          tester.getSize(sdSizedBoxFinder).height,
          equals(54.0),
        );

        // Verify Step 0 bottom primary action button height (54 px) and radius (14 px)
        final startBtnFinder = find.widgetWithText(
          CupertinoButton,
          'SPUSTIT ZÁZNAM JÍZDY',
        );
        expect(startBtnFinder, findsOneWidget);
        expect(tester.getSize(startBtnFinder).height, equals(54.0));
        final startBtnWidget = tester.widget<CupertinoButton>(startBtnFinder);
        expect(
          startBtnWidget.borderRadius,
          equals(BorderRadius.circular(14.0)),
        );

        // Transition to Step 1: Recording View
        await tester.tap(startBtnFinder);
        await tester.pump();

        expect(find.text('PROBÍHÁ ZÁZNAM JÍZDY'), findsOneWidget);
        expect(find.text('Zachycené CAN zprávy'), findsOneWidget);
        expect(find.text('Unikátní CAN ID sběrnice'), findsOneWidget);

        final stopBtnFinder = find.widgetWithText(
          CupertinoButton,
          'DOKONČIT A VYGENEROVAT PRO AI',
        );
        expect(stopBtnFinder, findsOneWidget);
        expect(tester.getSize(stopBtnFinder).height, equals(54.0));
        final stopBtnWidget = tester.widget<CupertinoButton>(stopBtnFinder);
        expect(
          stopBtnWidget.borderRadius,
          equals(BorderRadius.circular(14.0)),
        );

        // Transition to Step 2: Completed / Export View
        await tester.tap(stopBtnFinder);
        await tester.pump();

        expect(find.text('Podklady pro AI jsou připraveny'), findsOneWidget);

        // Verify Copy Prompt button height (54 px) and border radius (14 px)
        final copyBtnFinder = find.widgetWithText(
          CupertinoButton,
          'KOPÍROVAT PROMPT DO SCHRÁNKY',
        );
        expect(copyBtnFinder, findsOneWidget);
        expect(tester.getSize(copyBtnFinder).height, equals(54.0));
        final copyBtnWidget = tester.widget<CupertinoButton>(copyBtnFinder);
        expect(
          copyBtnWidget.borderRadius,
          equals(BorderRadius.circular(14.0)),
        );

        // Verify Share Dataset button height (54 px) and border radius (14 px)
        final shareBtnFinder = find.widgetWithText(
          CupertinoButton,
          'SDÍLET SOUBOR S DATY PRO AI',
        );
        expect(shareBtnFinder, findsOneWidget);
        expect(tester.getSize(shareBtnFinder).height, equals(54.0));
        final shareBtnWidget = tester.widget<CupertinoButton>(shareBtnFinder);
        expect(
          shareBtnWidget.borderRadius,
          equals(BorderRadius.circular(14.0)),
        );

        // Verify Paste AI Response bottom button height (54 px) and border radius (14 px)
        final pasteBtnFinder = find.widgetWithText(
          CupertinoButton,
          'VLOŽIT ODPOVĚĎ OD AI',
        );
        expect(pasteBtnFinder, findsOneWidget);
        expect(tester.getSize(pasteBtnFinder).height, equals(54.0));
        final pasteBtnWidget = tester.widget<CupertinoButton>(pasteBtnFinder);
        expect(
          pasteBtnWidget.borderRadius,
          equals(BorderRadius.circular(14.0)),
        );

        // Test copying the AI prompt updates state to PROMPT ZKOPÍROVÁN
        await tester.ensureVisible(copyBtnFinder);
        await tester.tap(copyBtnFinder);
        await tester.pump();
        expect(find.text('PROMPT ZKOPÍROVÁN'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        telemetryManager.dispose();
        bleService.dispose();
        gpsService.dispose();
      },
    );
  });
}
