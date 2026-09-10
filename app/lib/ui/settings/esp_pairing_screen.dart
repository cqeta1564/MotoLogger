import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/ble_service.dart';
import '../../services/telemetry_manager.dart';

/// Screen for scanning and pairing a new MotoLogger ESP32 unit.
/// Built strictly to Apple Human Interface Guidelines:
/// - Light Cupertino aesthetic (#F2F2F7 background, #FFFFFF cards)
/// - Radar search pulse animation
/// - Discovered hardware list with RSSI signal indicators
/// - 54 px button height alignment
class EspPairingScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;

  const EspPairingScreen({super.key, required this.telemetryManager});

  @override
  State<EspPairingScreen> createState() => _EspPairingScreenState();
}

class _EspPairingScreenState extends State<EspPairingScreen>
    with SingleTickerProviderStateMixin {
  late final BleService _ble;
  StreamSubscription? _scanSub;
  List<DiscoveredBleDevice> _devices = [];
  String? _pairingDeviceId;
  bool _isScanning = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _ble = widget.telemetryManager.bleService;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    _devices = List.from(_ble.discoveredDevices);
    _scanSub = _ble.discoveredDevicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    });

    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _pulseController.dispose();
    _ble.stopDiscoveryScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
    });
    await _ble.startDiscoveryScan();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _pairDevice(DiscoveredBleDevice device) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _pairingDeviceId = device.id;
    });

    final success = await widget.telemetryManager.pairDevice(device);

    if (!mounted) return;

    setState(() {
      _pairingDeviceId = null;
    });

    if (success) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1C1C1E),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.appleGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Spárováno s jednotkou ${device.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: '-apple-system',
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      // Return to settings after confirmation
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.appleRed,
          content: const Text(
            'Párování se nezdařilo. Zkontrolujte, zda je jednotka zapnutá.',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPairedId = widget.telemetryManager.pairedDeviceId;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Párování jednotky'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.clear),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                children: [
                  // Radar Scanning Animation & Header
                  Center(
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer expanding pulse ring
                              Container(
                                width: 70 + (90 * _pulseAnimation.value),
                                height: 70 + (90 * _pulseAnimation.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.appleBlue.withValues(
                                      alpha: (1.0 - _pulseAnimation.value) * 0.4,
                                    ),
                                    width: 2,
                                  ),
                                ),
                              ),
                              // Middle pulse ring
                              Container(
                                width: 50 + (60 * _pulseAnimation.value),
                                height: 50 + (60 * _pulseAnimation.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.appleBlue.withValues(
                                    alpha: (1.0 - _pulseAnimation.value) * 0.1,
                                  ),
                                ),
                              ),
                              // Core icon bubble
                              Container(
                                width: 74,
                                height: 74,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFE5E5EA), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.bluetooth_searching_rounded,
                                  color: AppTheme.appleBlue,
                                  size: 36,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Text(
                    'Hledám jednotky v dosahu',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.appleBlack,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      fontFamily: '-apple-system',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Ujistěte se, že je zapalování motocyklu zapnuté a telemetrická jednotka je napájena.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.appleMutedGray,
                        fontSize: 13,
                        height: 1.35,
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Section Title
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                    child: Text(
                      'DOSTUPNÉ JEDNOTKY (${_devices.length})',
                      style: const TextStyle(
                        color: AppTheme.appleMutedGray,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ),

                  // Discovered Devices Inset Group
                  if (_devices.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(radius: 12),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning
                                ? 'Skenuji okolní Bluetooth pásmo...'
                                : 'V dosahu nebyla nalezena žádná jednotka.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.appleMutedGray,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              fontFamily: '-apple-system',
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _devices.length,
                          separatorBuilder: (context, index) => const Divider(
                            color: Color(0xFFE5E5EA),
                            height: 1,
                            indent: 64,
                          ),
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final isCurrentPaired = currentPairedId != null &&
                                device.id.toLowerCase() == currentPairedId.toLowerCase();
                            final isPairing = _pairingDeviceId == device.id;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  // Hardware icon
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: device.isMotoLogger
                                          ? AppTheme.appleBlue.withValues(alpha: 0.12)
                                          : const Color(0xFFF2F2F7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      device.isMotoLogger
                                          ? Icons.developer_board_rounded
                                          : Icons.bluetooth_rounded,
                                      color: device.isMotoLogger
                                          ? AppTheme.appleBlue
                                          : AppTheme.appleMutedGray,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Device info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                device.name,
                                                style: const TextStyle(
                                                  color: AppTheme.appleBlack,
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -0.3,
                                                  fontFamily: '-apple-system',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (device.isMotoLogger) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.appleBlue.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'MotoLogger',
                                                  style: TextStyle(
                                                    color: AppTheme.appleBlue,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: '-apple-system',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            _buildSignalBars(device.signalBars),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${device.id} • ${device.rssi} dBm',
                                              style: const TextStyle(
                                                color: AppTheme.appleMutedGray,
                                                fontSize: 11.5,
                                                fontFamily: '-apple-system',
                                                fontFeatures: [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Action Button / Status
                                  if (isPairing)
                                    const CupertinoActivityIndicator(radius: 11)
                                  else if (isCurrentPaired)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.appleGreen.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: AppTheme.appleGreen,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Spárováno',
                                            style: TextStyle(
                                              color: AppTheme.appleGreen,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              fontFamily: '-apple-system',
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      color: AppTheme.appleBlue,
                                      borderRadius: BorderRadius.circular(16),
                                      onPressed: () => _pairDevice(device),
                                      child: const Text(
                                        'Spárovat',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: '-apple-system',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Fixed Bottom Action Button (Apple 54 px standard)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _isScanning ? null : _startScan,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: _isScanning ? AppTheme.appleMutedGray : AppTheme.appleBlack,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isScanning ? 'Hledám...' : 'Znovu vyhledat',
                        style: TextStyle(
                          color: _isScanning ? AppTheme.appleMutedGray : AppTheme.appleBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          fontFamily: '-apple-system',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Minimalist signal strength bars (1 to 4 bars)
  Widget _buildSignalBars(int bars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final barIndex = i + 1;
        final isActive = barIndex <= bars;
        Color color = AppTheme.appleMutedGray.withValues(alpha: 0.3);
        if (isActive) {
          if (bars >= 3) {
            color = AppTheme.appleGreen;
          } else if (bars == 2) {
            color = AppTheme.appleOrange;
          } else {
            color = AppTheme.appleRed;
          }
        }

        return Container(
          width: 2.5,
          height: 4.0 + (i * 2.5),
          margin: const EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
