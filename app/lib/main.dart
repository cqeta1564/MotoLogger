import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'services/ble_service.dart';
import 'services/gps_service.dart';
import 'services/database_service.dart';
import 'services/telemetry_manager.dart';
import 'ui/dashboard/dashboard_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/settings/settings_screen.dart';

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
      DashboardScreen(telemetryManager: widget.telemetryManager),
      HistoryScreen(dbService: widget.dbService),
      SettingsScreen(telemetryManager: widget.telemetryManager),
    ];

    return MaterialApp(
      title: 'MotoLogger',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: screens[_selectedTabIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          onTap: (idx) => setState(() => _selectedTabIndex = idx),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.speed),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Sessions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
