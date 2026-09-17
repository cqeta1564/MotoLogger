import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/preferences/app_preferences.dart';
import 'services/ble_service.dart';
import 'services/gps_service.dart';
import 'services/database_service.dart';
import 'services/telemetry_manager.dart';
import 'ui/dashboard/dashboard_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/widgets/apple_tab_bar.dart';
import 'ui/widgets/tab_content_transition.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bleService = BleService();
  final gpsService = GpsService();
  final dbService = DatabaseService.instance;

  final telemetryManager = TelemetryManager(
    bleService: bleService,
    gpsService: gpsService,
    dbService: dbService,
  );

  runApp(MotoLoggerApp(
    telemetryManager: telemetryManager,
    dbService: dbService,
  ));
  // Render the application before permission prompts or slow device discovery.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await gpsService.initialize();
    await bleService.startScanAndAutoConnect();
  });
}

class MotoLoggerApp extends StatefulWidget {
  final TelemetryManager telemetryManager;
  final DatabaseService dbService;

  const MotoLoggerApp({
    super.key,
    required this.telemetryManager,
    required this.dbService,
  });

  @override
  State<MotoLoggerApp> createState() => _MotoLoggerAppState();
}

class _MotoLoggerAppState extends State<MotoLoggerApp> {
  int _selectedTabIndex = 0;
  bool _rideLocked = false;
  late final AppPreferences _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = AppPreferences(widget.dbService)..load();
  }

  @override
  void dispose() {
    _preferences.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedTabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return AppPreferencesScope(
      preferences: _preferences,
      child: MaterialApp(
        title: 'MotoLogger',
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: child!,
        ),
        home: Builder(
            builder: (context) => PopScope(
                  canPop: _selectedTabIndex == 0,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) _selectTab(0);
                  },
                  child: Scaffold(
                    backgroundColor: AppTheme.surfaceSecondary,
                    body: Stack(children: [
                      TabContentTransition(
                          index: _selectedTabIndex,
                          child:
                              IndexedStack(index: _selectedTabIndex, children: [
                            DashboardScreen(
                              telemetryManager: widget.telemetryManager,
                              onNavigateTab: _selectTab,
                              onLockChanged: (value) =>
                                  setState(() => _rideLocked = value),
                            ),
                            HistoryScreen(
                                dbService: widget.dbService,
                                telemetryManager: widget.telemetryManager),
                            SettingsScreen(
                                telemetryManager: widget.telemetryManager),
                          ])),
                      if (!(_selectedTabIndex == 0 && _rideLocked) &&
                          MediaQuery.viewInsetsOf(context).bottom == 0)
                        Positioned(
                            left: 20,
                            right: 20,
                            bottom: 12 + MediaQuery.paddingOf(context).bottom,
                            child: Center(
                                child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 540),
                              child: AppleTabBar(
                                  currentIndex: _selectedTabIndex,
                                  onTabSelected: _selectTab),
                            ))),
                    ]),
                  ),
                )),
      ),
    );
  }
}
