import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'services/ble_service.dart';
import 'services/gps_service.dart';
import 'services/database_service.dart';
import 'services/telemetry_manager.dart';
import 'ui/dashboard/dashboard_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/widgets/apple_tab_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bleService = BleService();
  final gpsService = GpsService();
  final dbService = DatabaseService.instance;

  await gpsService.initialize();
  bleService.startScanAndAutoConnect();

  final telemetryManager = TelemetryManager(
    bleService: bleService,
    gpsService: gpsService,
    dbService: dbService,
  );

  runApp(MotoLoggerApp(
    telemetryManager: telemetryManager,
    dbService: dbService,
  ));
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

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        telemetryManager: widget.telemetryManager,
        onNavigateTab: (idx) => setState(() => _selectedTabIndex = idx),
      ),
      HistoryScreen(dbService: widget.dbService),
      SettingsScreen(telemetryManager: widget.telemetryManager),
    ];

    return MaterialApp(
      title: 'MotoLogger',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: screens[_selectedTabIndex],
        bottomNavigationBar: _selectedTabIndex == 0
            ? null
            : AppleTabBar(
                currentIndex: _selectedTabIndex,
                onTabSelected: (idx) => setState(() => _selectedTabIndex = idx),
              ),
      ),
    );
  }
}
