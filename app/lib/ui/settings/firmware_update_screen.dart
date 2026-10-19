import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/ble_service.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/glass_surface.dart';
import 'settings_screen.dart';

/// Screen for wireless on-demand Wi-Fi OTA firmware updates.
/// Allows riders to activate a standalone SoftAP ("MotoLogger-OTA")
/// to flash new firmware (.bin) via standard browser without USB cables.
class FirmwareUpdateScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;

  const FirmwareUpdateScreen({
    super.key,
    required this.telemetryManager,
  });

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends State<FirmwareUpdateScreen> {
  bool _busy = false;

  TelemetryManager get manager => widget.telemetryManager;
  BleService get ble => manager.bleService;

  Future<void> _toggleOtaMode() async {
    if (_busy) return;
    final speed = manager.latestPacket.vehicleSpeedKmh;
    if (speed > 5 && !ble.isOtaModeActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Z bezpečnostních důvodů nelze aktualizaci spustit za jízdy (> 5 km/h).'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final target = !ble.isOtaModeActive;
      final ok = await manager.setOtaMode(target);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Příkaz pro OTA režim se nepodařilo potvrdit. Zkontrolujte připojení.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při přepínání OTA: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label byl zkopírován do schránky.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatOtaStatus(int stateCode) {
    switch (stateCode) {
      case 1:
        return 'Čeká na připojení a nahrání souboru';
      case 2:
        return 'Probíhá zápis nového firmwaru do flash paměti…';
      case 3:
        return 'Aktualizace úspěšná! Jednotka se restartuje…';
      case 4:
        return 'Aktualizace byla odmítnuta nebo selhala.';
      default:
        return 'Režim aktualizace je vypnut';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final connected = ble.state == BleConnectionState.connected;
        final demo = manager.isSimulationMode;
        final available = connected || demo;
        final isOtaActive = ble.isOtaModeActive;
        final speed = manager.latestPacket.vehicleSpeedKmh;
        final isMoving = speed > 5;

        return Scaffold(
          backgroundColor: AppTheme.surfaceSecondary,
          appBar: AppBar(
            backgroundColor: AppTheme.surfaceSecondary,
            elevation: 0,
            leading: const GlassBackButton(),
            title: const Text(
              'Aktualizace firmwaru',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // Movement warning if motorcycle is running/moving
                      if (isMoving && !isOtaActive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            border: Border.all(color: Colors.amber.shade300),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.exclamationmark_triangle_fill,
                                  color: Colors.amber.shade800, size: 24),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Motocykl je v pohybu. Aktualizaci lze provést pouze při zastavení na místě.',
                                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Main Card
                      ContentGroup(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isOtaActive
                                        ? Colors.green.shade50
                                        : AppTheme.surfaceSecondary,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isOtaActive
                                        ? CupertinoIcons.wifi
                                        : CupertinoIcons.arrow_clockwise_circle,
                                    color: isOtaActive
                                        ? Colors.green.shade700
                                        : AppTheme.appleBlue,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isOtaActive
                                            ? 'Wi-Fi AP aktivní'
                                            : 'Bezdrátový flash (OTA)',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isOtaActive
                                            ? 'Jednotka vysílá servisní síť'
                                            : 'Nahrání nového firmwaru bez kabelu',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isOtaActive
                                  ? 'Klepnutím na údaje níže je můžete zkopírovat do schránky:'
                                  : 'Režim bezdrátové aktualizace spustí na jednotce dočasný Wi-Fi přístupový bod. Přes něj otevřete v prohlížeči jednoduchou stránku a nahrajete zkompilovaný binární soubor firmwaru.',
                              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Connection details card if OTA active
                      if (isOtaActive) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text(
                            'PŘÍSTUPOVÉ ÚDAJE SÍTĚ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        ContentGroup(
                          child: Column(
                            children: [
                              SettingsRow(
                                icon: CupertinoIcons.wifi,
                                title: 'Název Wi-Fi (SSID)',
                                subtitle: 'MotoLogger-OTA',
                                trailing: const Icon(CupertinoIcons.doc_on_doc,
                                    size: 18, color: AppTheme.appleBlue),
                                navigates: false,
                                onTap: () => _copyToClipboard('MotoLogger-OTA', 'Název Wi-Fi (SSID)'),
                              ),
                              const Divider(height: 1, indent: 56, color: AppTheme.appleBorder),
                              SettingsRow(
                                icon: CupertinoIcons.lock,
                                title: 'Heslo k síti',
                                subtitle: 'motologger',
                                trailing: const Icon(CupertinoIcons.doc_on_doc,
                                    size: 18, color: AppTheme.appleBlue),
                                navigates: false,
                                onTap: () => _copyToClipboard('motologger', 'Heslo k síti'),
                              ),
                              const Divider(height: 1, indent: 56, color: AppTheme.appleBorder),
                              SettingsRow(
                                icon: CupertinoIcons.globe,
                                title: 'Webová adresa',
                                subtitle: 'http://${ble.otaIpAddress}',
                                trailing: const Icon(CupertinoIcons.doc_on_doc,
                                    size: 18, color: AppTheme.appleBlue),
                                navigates: false,
                                onTap: () => _copyToClipboard(
                                    'http://${ble.otaIpAddress}', 'Webová adresa'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text(
                            'POSTUP AKTUALIZACE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        ContentGroup(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStepRow(1, 'V nastavení telefonu se připojte k síti MotoLogger-OTA.'),
                              const SizedBox(height: 10),
                              _buildStepRow(2, 'Otevřete webový prohlížeč na adrese http://${ble.otaIpAddress}.'),
                              const SizedBox(height: 10),
                              _buildStepRow(3, 'Klepněte na "Vybrat soubor" a zvolte nový firmware.bin.'),
                              const SizedBox(height: 10),
                              _buildStepRow(4, 'Klepněte na "Flash Firmware". Po zápisu se jednotka restartuje.'),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // OTA live state indicator
                        ContentGroup(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              if (ble.otaStateCode == 2)
                                const CupertinoActivityIndicator()
                              else
                                Icon(
                                  ble.otaStateCode == 3
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons.info_circle_fill,
                                  color: ble.otaStateCode == 3
                                      ? Colors.green
                                      : AppTheme.appleBlue,
                                  size: 22,
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _formatOtaStatus(ble.otaStateCode),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Bottom Action Button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: PrimaryAction(
                    label: isOtaActive
                        ? 'Ukončit režim aktualizace'
                        : 'Aktivovat Wi-Fi aktualizaci',
                    icon: isOtaActive
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.wifi,
                    busy: _busy,
                    onPressed: (!available || (isMoving && !isOtaActive))
                        ? null
                        : _toggleOtaMode,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepRow(int step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.appleBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.appleBlue,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
