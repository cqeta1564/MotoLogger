import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants/ble_constants.dart';
import '../models/telemetry_packet.dart';
import '../models/can_profile.dart';

import 'database_service.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error
}

/// Discovered BLE device representation for pairing and UI display.
class DiscoveredBleDevice {
  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice? device;
  final bool isMotoLogger;

  const DiscoveredBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.device,
    this.isMotoLogger = false,
  });

  /// Approximate signal strength percentage (0 - 100%)
  int get signalStrengthPercent {
    return ((rssi + 100) * (100 / 60)).round().clamp(0, 100);
  }

  /// Signal bars from 1 to 4 based on RSSI dBm
  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -85) return 2;
    return 1;
  }
}

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _telemetryChar;
  BluetoothCharacteristic? _commandChar;

  BleConnectionState _state = BleConnectionState.disconnected;
  final _stateController = StreamController<BleConnectionState>.broadcast();
  final _telemetryController = StreamController<TelemetryPacket>.broadcast();

  Stream<BleConnectionState> get stateStream => _stateController.stream;
  Stream<TelemetryPacket> get telemetryStream => _telemetryController.stream;
  BleConnectionState get state => _state;

  // Paired device persistence
  String? _pairedDeviceId;
  String? _pairedDeviceName;
  String? get pairedDeviceId => _pairedDeviceId;
  String? get pairedDeviceName => _pairedDeviceName;
  bool get isPaired => _pairedDeviceId != null && _pairedDeviceId!.isNotEmpty;

  // Device discovery scanning
  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;
  final List<DiscoveredBleDevice> _discoveredDevices = [];
  final _discoveredDevicesController = StreamController<List<DiscoveredBleDevice>>.broadcast();
  Stream<List<DiscoveredBleDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;
  List<DiscoveredBleDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  StreamSubscription? _scanSubscription;
  StreamSubscription? _discoveryScanSubscription;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _mockTimer;
  bool _mockMode = false;
  bool get isMockMode => _mockMode;

  final List<Timer> _mockScanTimers = [];

  void _setState(BleConnectionState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  /// Initialize paired device identity from local database
  Future<void> initPairedDevice({required DatabaseService dbService}) async {
    try {
      final savedId = await dbService.getSetting('paired_device_id');
      final savedName = await dbService.getSetting('paired_device_name');
      if (savedId != null && savedId.isNotEmpty) {
        _pairedDeviceId = savedId;
        _pairedDeviceName = savedName;
        debugPrint('[BLE] Loaded paired device: $_pairedDeviceName ($_pairedDeviceId)');
      }
      _stateController.add(_state);
    } catch (e) {
      debugPrint('[BLE] Error loading paired device: $e');
    }
  }

  Future<void> startScanAndAutoConnect() async {
    if (_mockMode) return;
    if (_state == BleConnectionState.connecting || _state == BleConnectionState.connected) {
      return;
    }

    _setState(BleConnectionState.scanning);

    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('[BLE] Bluetooth not supported on this device.');
        _setState(BleConnectionState.error);
        return;
      }

      await FlutterBluePlus.startScan(
        withServices: [Guid(BleConstants.serviceUuid)],
        timeout: const Duration(seconds: 15),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          final deviceId = r.device.remoteId.str.toLowerCase();
          final isTargetDevice = (_pairedDeviceId != null && _pairedDeviceId!.isNotEmpty)
              ? (deviceId == _pairedDeviceId!.toLowerCase())
              : (r.device.platformName == BleConstants.deviceName ||
                  r.advertisementData.serviceUuids.contains(Guid(BleConstants.serviceUuid)));

          if (isTargetDevice) {
            debugPrint('[BLE] Found MotoLogger device: ${r.device.remoteId}');
            await FlutterBluePlus.stopScan();
            await connect(r.device);
            break;
          }
        }
      });
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
      _setState(BleConnectionState.error);
    }
  }

  /// Start searching for all nearby BLE devices for pairing
  Future<void> startDiscoveryScan() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveredDevices.clear();
    _discoveredDevicesController.add(List.unmodifiable(_discoveredDevices));

    for (final t in _mockScanTimers) {
      t.cancel();
    }
    _mockScanTimers.clear();

    if (_mockMode) {
      // In mock mode, simulate realistic MotoLogger and peripheral BLE discovery
      _mockScanTimers.add(Timer(const Duration(milliseconds: 300), () {
        if (!_isDiscovering) return;
        _discoveredDevices.add(const DiscoveredBleDevice(
          id: 'C4:DE:E2:81:4A:12',
          name: 'MotoLogger-ESP32 (Vpředu)',
          rssi: -54,
          isMotoLogger: true,
        ));
        _discoveredDevicesController.add(List.unmodifiable(_discoveredDevices));
      }));

      _mockScanTimers.add(Timer(const Duration(milliseconds: 700), () {
        if (!_isDiscovering) return;
        _discoveredDevices.add(const DiscoveredBleDevice(
          id: 'E8:9F:6D:32:B1:09',
          name: 'MotoLogger-ESP32 #2',
          rssi: -76,
          isMotoLogger: true,
        ));
        _discoveredDevicesController.add(List.unmodifiable(_discoveredDevices));
      }));

      _mockScanTimers.add(Timer(const Duration(milliseconds: 1100), () {
        if (!_isDiscovering) return;
        _discoveredDevices.add(const DiscoveredBleDevice(
          id: 'F0:17:88:AC:20:94',
          name: 'OBDII-CAN-Link',
          rssi: -84,
          isMotoLogger: false,
        ));
        _discoveredDevicesController.add(List.unmodifiable(_discoveredDevices));
      }));
      return;
    }

    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('[BLE] Bluetooth not supported on this device.');
        _isDiscovering = false;
        return;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));

      _discoveryScanSubscription?.cancel();
      _discoveryScanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final id = r.device.remoteId.str;
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : 'BLE Zařízení');
          final isMoto = name == BleConstants.deviceName ||
              name.contains('MotoLogger') ||
              name.contains('ESP32') ||
              r.advertisementData.serviceUuids.contains(Guid(BleConstants.serviceUuid));

          final existingIndex = _discoveredDevices.indexWhere((d) => d.id == id);
          final discovered = DiscoveredBleDevice(
            id: id,
            name: name,
            rssi: r.rssi,
            device: r.device,
            isMotoLogger: isMoto,
          );

          if (existingIndex >= 0) {
            _discoveredDevices[existingIndex] = discovered;
          } else {
            _discoveredDevices.add(discovered);
          }
        }

        // Sort MotoLogger units first, then highest RSSI
        _discoveredDevices.sort((a, b) {
          if (a.isMotoLogger && !b.isMotoLogger) return -1;
          if (!a.isMotoLogger && b.isMotoLogger) return 1;
          return b.rssi.compareTo(a.rssi);
        });

        _discoveredDevicesController.add(List.unmodifiable(_discoveredDevices));
      });
    } catch (e) {
      debugPrint('[BLE] Discovery scan error: $e');
      _isDiscovering = false;
    }
  }

  /// Stop discovery scan
  Future<void> stopDiscoveryScan() async {
    _isDiscovering = false;
    for (final t in _mockScanTimers) {
      t.cancel();
    }
    _mockScanTimers.clear();
    _discoveryScanSubscription?.cancel();
    _discoveryScanSubscription = null;
    if (!_mockMode) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  /// Pair a specific discovered device and save to SQLite
  Future<bool> pairDevice(DiscoveredBleDevice discovered, {required DatabaseService dbService}) async {
    _pairedDeviceId = discovered.id;
    _pairedDeviceName = discovered.name;
    await dbService.saveSetting('paired_device_id', discovered.id);
    await dbService.saveSetting('paired_device_name', discovered.name);
    debugPrint('[BLE] Paired with device: ${discovered.name} (${discovered.id})');

    if (_mockMode) {
      _setState(BleConnectionState.connected);
      return true;
    }

    if (discovered.device != null) {
      await connect(discovered.device!);
      return true;
    }
    return true;
  }

  /// Unpair and forget the active ESP device
  Future<void> unpairDevice({required DatabaseService dbService}) async {
    disconnect();
    _pairedDeviceId = null;
    _pairedDeviceName = null;
    await dbService.removeSetting('paired_device_id');
    await dbService.removeSetting('paired_device_name');
    debugPrint('[BLE] Device forgotten and unpaired.');
    _setState(BleConnectionState.disconnected);
  }

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _setState(BleConnectionState.connecting);

    try {
      await _device!.connect(autoConnect: true, timeout: const Duration(seconds: 10));

      _connectionSubscription = _device!.connectionState.listen((BluetoothConnectionState s) {
        if (s == BluetoothConnectionState.connected) {
          _setState(BleConnectionState.connected);
          _discoverServices();
        } else if (s == BluetoothConnectionState.disconnected) {
          _setState(BleConnectionState.disconnected);
          debugPrint('[BLE] Disconnected. Re-starting auto scan...');
          startScanAndAutoConnect();
        }
      });
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _setState(BleConnectionState.error);
    }
  }

  Future<void> _discoverServices() async {
    if (_device == null) return;

    try {
      List<BluetoothService> services = await _device!.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid(BleConstants.serviceUuid)) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid(BleConstants.telemetryCharUuid)) {
              _telemetryChar = c;
              await _subscribeToTelemetry();
            } else if (c.uuid == Guid(BleConstants.commandCharUuid)) {
              _commandChar = c;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] Service discovery error: $e');
    }
  }

  Future<void> _subscribeToTelemetry() async {
    if (_telemetryChar == null) return;

    try {
      await _telemetryChar!.setNotifyValue(true);
      _notifySubscription = _telemetryChar!.onValueReceived.listen((List<int> value) {
        if (value.isNotEmpty) {
          try {
            final packet = TelemetryPacket.fromBytes(Uint8List.fromList(value));
            _telemetryController.add(packet);
          } catch (e) {
            debugPrint('[BLE] Deserialization error: $e');
          }
        }
      });
      debugPrint('[BLE] Subscribed to 25 Hz telemetry notifications.');
    } catch (e) {
      debugPrint('[BLE] Notification subscription error: $e');
    }
  }

  Future<bool> sendTareZero() async {
    if (_mockMode) {
      debugPrint('[BLE MOCK] Tare Zero calibrated!');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      await _commandChar!.write([BleConstants.cmdTareZero], withoutResponse: true);
      debugPrint('[BLE] Sent Tare Zero command to ESP32.');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send Tare Zero command: $e');
      return false;
    }
  }

  Future<bool> sendTareOffset(double offsetDeg) async {
    if (_mockMode) {
      debugPrint('[BLE MOCK] Tare mounting offset calibrated: ${offsetDeg.toStringAsFixed(1)}°');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      // Encode offset in tenths of a degree (int16_t, Little-Endian)
      final offsetInt16 = (offsetDeg * 10).round().clamp(-32768, 32767);
      final byteData = ByteData(3);
      byteData.setUint8(0, BleConstants.cmdTareWithOffset);
      byteData.setInt16(1, offsetInt16, Endian.little);

      await _commandChar!.write(byteData.buffer.asUint8List(), withoutResponse: true);
      debugPrint('[BLE] Sent Tare Offset command (${offsetDeg.toStringAsFixed(1)}°) to ESP32.');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send Tare Offset command: $e');
      return false;
    }
  }

  Future<bool> sendCanSignalConfig({
    required int signalIndex,
    required CanSignalMapping mapping,
  }) async {
    if (_mockMode) {
      debugPrint('[BLE MOCK] Sent CAN signal config for index $signalIndex (ID: ${mapping.canId})');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      // 17 bytes: cmd (1B), signal (1B), canId (4B), startByte (1B), len (1B), endian (1B), mult (4B), offset (4B)
      final byteData = ByteData(17);
      byteData.setUint8(0, BleConstants.cmdSetCanSignal);
      byteData.setUint8(1, signalIndex);
      byteData.setUint32(2, mapping.numericCanId, Endian.little);
      byteData.setUint8(6, mapping.startByte);
      byteData.setUint8(7, mapping.lengthBytes);
      byteData.setUint8(8, mapping.isBigEndian ? 1 : 0);
      byteData.setFloat32(9, mapping.multiplier, Endian.little);
      byteData.setFloat32(13, mapping.offset, Endian.little);

      await _commandChar!.write(byteData.buffer.asUint8List(), withoutResponse: true);
      debugPrint('[BLE] Sent CAN signal config for index $signalIndex (ID: ${mapping.canId})');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send CAN signal config: $e');
      return false;
    }
  }

  Future<bool> sendCanProfileMode({required bool isCustomActive}) async {
    if (_mockMode) {
      debugPrint('[BLE MOCK] Set CAN profile mode to: $isCustomActive');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      final bytes = [BleConstants.cmdSetCanProfileMode, isCustomActive ? 1 : 0];
      await _commandChar!.write(bytes, withoutResponse: true);
      debugPrint('[BLE] Sent CAN profile mode command: $isCustomActive');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send CAN profile mode command: $e');
      return false;
    }
  }

  Future<bool> uploadBikeProfile(BikeProfile profile) async {
    if (profile.id == 'standard_obd2') {
      return await sendCanProfileMode(isCustomActive: false);
    }

    bool success = true;
    if (profile.rpmSignal != null) {
      success &= await sendCanSignalConfig(
        signalIndex: BleConstants.canSignalRpm,
        mapping: profile.rpmSignal!,
      );
    }
    if (profile.speedSignal != null) {
      success &= await sendCanSignalConfig(
        signalIndex: BleConstants.canSignalSpeed,
        mapping: profile.speedSignal!,
      );
    }
    if (profile.throttleSignal != null) {
      success &= await sendCanSignalConfig(
        signalIndex: BleConstants.canSignalThrottle,
        mapping: profile.throttleSignal!,
      );
    }
    if (profile.gearSignal != null) {
      success &= await sendCanSignalConfig(
        signalIndex: BleConstants.canSignalGear,
        mapping: profile.gearSignal!,
      );
    }
    if (profile.coolantSignal != null) {
      success &= await sendCanSignalConfig(
        signalIndex: BleConstants.canSignalCoolant,
        mapping: profile.coolantSignal!,
      );
    }

    success &= await sendCanProfileMode(isCustomActive: true);
    return success;
  }

  // Built-in Demo / Simulation generator for UI testing without real bike
  void enableMockMode(bool enable) {
    _mockMode = enable;
    if (enable) {
      _mockTimer?.cancel();
      _setState(BleConnectionState.connected);
      double time = 0.0;

      _mockTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
        time += 0.04;
        // Generate realistic motorcycle lean curve (sweeper corners)
        double lean = 44.0 * sin(time * 0.8);
        double pitch = 4.0 * cos(time * 0.8);
        int rpm = (5000 + 4500 * sin(time * 0.5).abs()).toInt();
        int speed = (60 + 55 * sin(time * 0.5).abs()).toInt();
        int gear = (speed / 20).clamp(1, 6).toInt();

        final mockPacket = TelemetryPacket(
          timestampMs: (time * 1000).toInt(),
          leanAngleDeg: lean,
          pitchDeg: pitch,
          accelXG: 0.35 * cos(time * 0.8),
          accelYG: (lean / 45.0) * 1.1,
          accelZG: 1.0 + 0.2 * sin(time),
          gyroXDps: 15.0 * cos(time * 0.4),
          gyroYDps: 5.0 * sin(time * 0.8),
          gyroZDps: 20.0 * sin(time * 0.4),
          engineRpm: rpm,
          vehicleSpeedKmh: speed,
          throttlePosPct: (40 + 35 * sin(time * 0.5)).clamp(0, 100).toInt(),
          coolantTempC: 88,
          gear: gear,
          batteryVoltage: 14.2,
          statusFlags: 0x0F, // SD OK, Engine Run, IMU OK
        );

        _telemetryController.add(mockPacket);
      });
    } else {
      _mockTimer?.cancel();
      _mockTimer = null;
      _setState(BleConnectionState.disconnected);
      _telemetryController.add(const TelemetryPacket(
        timestampMs: 0,
        leanAngleDeg: 0.0,
        pitchDeg: 0.0,
        accelXG: 0.0,
        accelYG: 0.0,
        accelZG: 1.0,
        gyroXDps: 0.0,
        gyroYDps: 0.0,
        gyroZDps: 0.0,
        engineRpm: 0,
        vehicleSpeedKmh: 0,
        throttlePosPct: 0,
        coolantTempC: 0,
        gear: 0,
        batteryVoltage: 12.6,
        statusFlags: 0,
      ));
    }
  }

  final List<String> _mockOfflineLogQueue = [];

  void setMockOfflineLogs(List<String> csvLogs) {
    _mockOfflineLogQueue.clear();
    _mockOfflineLogQueue.addAll(csvLogs);
  }

  void addMockOfflineLog(String csv) {
    _mockOfflineLogQueue.add(csv);
  }

  /// Checks ESP32 MicroSD for un-synced offline session logs
  Future<List<String>> checkOfflineLogs() async {
    if (_mockMode) {
      if (_mockOfflineLogQueue.isNotEmpty) {
        return List.generate(_mockOfflineLogQueue.length, (i) => 'LOG_${(i + 1).toString().padLeft(4, '0')}.CSV');
      }
      return [];
    }

    if (_commandChar == null) return [];

    try {
      final cmd = [BleConstants.cmdSyncCheck];
      await _commandChar!.write(cmd, withoutResponse: false);
      debugPrint('[BLE] Sent offline sync check command.');
      return [];
    } catch (e) {
      debugPrint('[BLE] checkOfflineLogs error: $e');
      return [];
    }
  }

  /// Downloads an offline session log by filename/id
  Future<String?> downloadOfflineLog(String logId) async {
    if (_mockMode) {
      if (_mockOfflineLogQueue.isNotEmpty) {
        return _mockOfflineLogQueue.first;
      }
      return null;
    }

    if (_commandChar == null) return null;

    try {
      final bytes = [BleConstants.cmdSyncRequestFile, ...utf8.encode(logId)];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Requested log file download: $logId');
      return null;
    } catch (e) {
      debugPrint('[BLE] downloadOfflineLog error: $e');
      return null;
    }
  }

  /// Acknowledges successful sync so ESP32 knows not to send it again
  Future<bool> acknowledgeOfflineLogSync(String logId) async {
    if (_mockMode) {
      if (_mockOfflineLogQueue.isNotEmpty) {
        _mockOfflineLogQueue.removeAt(0);
      }
      debugPrint('[BLE MOCK] Acknowledged offline log sync: $logId');
      return true;
    }

    if (_commandChar == null) return false;

    try {
      final bytes = [BleConstants.cmdSyncAck, ...utf8.encode(logId)];
      await _commandChar!.write(bytes, withoutResponse: true);
      debugPrint('[BLE] Acknowledged offline log sync: $logId');
      return true;
    } catch (e) {
      debugPrint('[BLE] acknowledgeOfflineLogSync error: $e');
      return false;
    }
  }

  void disconnect() {
    _mockTimer?.cancel();
    for (final t in _mockScanTimers) {
      t.cancel();
    }
    _mockScanTimers.clear();
    _scanSubscription?.cancel();
    _discoveryScanSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    _device?.disconnect();
    _setState(BleConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _telemetryController.close();
    _discoveredDevicesController.close();
  }
}
