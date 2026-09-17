import 'package:flutter/widgets.dart';
import '../../services/database_service.dart';

/// User-controlled material fallback where the OS exposes no reliable signal.
class AppPreferences extends ChangeNotifier {
  AppPreferences(this.database);
  final DatabaseService database;
  bool reduceTransparency = false;
  bool saving = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final value = await database.getSetting('reduce_transparency');
      if (_disposed) return;
      reduceTransparency = value == 'true';
      notifyListeners();
    } catch (_) {
      // Prefer legibility if the preference cannot be read.
      if (!_disposed) {
        reduceTransparency = true;
        notifyListeners();
      }
    }
  }

  Future<void> setReduceTransparency(bool value) async {
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      await database.saveSetting('reduce_transparency', '$value');
      if (!_disposed) reduceTransparency = value;
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppPreferencesScope extends InheritedNotifier<AppPreferences> {
  const AppPreferencesScope(
      {super.key, required AppPreferences preferences, required super.child})
      : super(notifier: preferences);

  static AppPreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppPreferencesScope>()
      ?.notifier;
}
