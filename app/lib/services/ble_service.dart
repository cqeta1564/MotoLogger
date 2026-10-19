import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants/ble_constants.dart';
import '../models/telemetry_packet.dart';
import '../models/can_profile.dart';
import '../models/dtc_code.dart';
import '../models/captured_can_frame.dart';

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

  // CAN Sniffer stream
  final _rawCanFrameController = StreamController<CapturedCanFrame>.broadcast();
  Stream<CapturedCanFrame> get rawCanFrameStream => _rawCanFrameController.stream;
  bool _isCanSnifferActive = false;
  bool get isCanSnifferActive => _isCanSnifferActive;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _discoveryScanSubscription;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _scanTimeoutTimer;
  Timer? _mockTimer;
  bool _mockMode = false;
  bool get isMockMode => _mockMode;
  bool mockStationary = false;

  final List<Timer> _mockScanTimers = [];

  // BLE offline file sync state
  Completer<List<String>>? _syncCheckCompleter;
  Completer<String?>? _syncFileCompleter;
  Completer<bool>? _syncAckCompleter;
  Timer? _chunkWatchdogTimer;
  final BytesBuilder _fileChunkBuffer = BytesBuilder();
  void Function(int bytesRead)? onSyncProgress;

  // Dedicated OBD-II Diagnostic Mode state & completers
  Completer<bool>? _diagModeCompleter;
  Completer<List<DiagnosticTroubleCode>>? _diagDtcListCompleter;
  Completer<bool>? _diagClearAckCompleter;
  bool _mockDiagModeActive = false;
  final List<DiagnosticTroubleCode> _mockDtcList = [
    const DiagnosticTroubleCode(code: 'P0122', isPending: false),
    const DiagnosticTroubleCode(code: 'C0035', isPending: true),
  ];

  // OTA Update state
  bool _isOtaModeActive = false;
  bool get isOtaModeActive => _isOtaModeActive;
  int _otaStateCode = 0; // 0=OFF, 1=READY_WAITING, 2=UPDATING, 3=SUCCESS_REBOOTING, 4=ERROR_REJECTED
  int get otaStateCode => _otaStateCode;
  String _otaIpAddress = '192.168.4.1';
  String get otaIpAddress => _otaIpAddress;
  Completer<bool>? _otaModeCompleter;

  void _setState(BleConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
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
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }
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
    _scanTimeoutTimer?.cancel();

    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('[BLE] Bluetooth not supported on this device.');
        _setState(BleConnectionState.error);
        return;
      }

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          final deviceId = r.device.remoteId.str.toLowerCase();
          final isTargetDevice = (_pairedDeviceId != null && _pairedDeviceId!.isNotEmpty)
              ? (deviceId == _pairedDeviceId!.toLowerCase())
              : (r.device.platformName == BleConstants.deviceName ||
                  r.advertisementData.serviceUuids.contains(Guid(BleConstants.serviceUuid)));

          if (isTargetDevice) {
            debugPrint('[BLE] Found MotoLogger device: ${r.device.remoteId}');
            _scanTimeoutTimer?.cancel();
            await FlutterBluePlus.stopScan();
            await connect(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(BleConstants.serviceUuid)],
        timeout: const Duration(seconds: 15),
      );

      _scanTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_state == BleConnectionState.scanning) {
          _setState(BleConnectionState.disconnected);
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
    _scanTimeoutTimer?.cancel();
    _device = device;
    _setState(BleConnectionState.connecting);

    try {
      await _device!.connect(autoConnect: true, timeout: const Duration(seconds: 10));

      await _connectionSubscription?.cancel();
      _connectionSubscription = _device!.connectionState.listen((BluetoothConnectionState s) async {
        if (s == BluetoothConnectionState.connected) {
          await _discoverServices();
          _setState(BleConnectionState.connected);
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
      // Request 256-byte MTU for 28B telemetry packets and 184B SD sync chunks
      try {
        await _device!.requestMtu(256);
      } catch (_) {}

      List<BluetoothService> services = await _device!.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid(BleConstants.serviceUuid)) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid(BleConstants.telemetryCharUuid)) {
              _telemetryChar = c;
              await _subscribeToTelemetry();
            } else if (c.uuid == Guid(BleConstants.commandCharUuid)) {
              _commandChar = c;
              await _subscribeToCommands();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] Service discovery error: $e');
    }
  }

  Future<void> _subscribeToCommands() async {
    if (_commandChar == null) return;

    try {
      await _commandChar!.setNotifyValue(true);
      await _commandSubscription?.cancel();
      _commandSubscription = _commandChar!.onValueReceived.listen((List<int> value) {
        _handleCommandResponse(value);
      });
      debugPrint('[BLE] Subscribed to command notifications.');
    } catch (e) {
      debugPrint('[BLE] Command notification subscription error: $e');
    }
  }

  void _resetChunkWatchdog() {
    _chunkWatchdogTimer?.cancel();
    _chunkWatchdogTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('[BLE] downloadOfflineLog chunk inactivity timeout (5s without packets).');
      final c = _syncFileCompleter;
      _syncFileCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete(null);
      }
    });
  }

  @visibleForTesting
  void handleCommandResponseForTest(List<int> value) => _handleCommandResponse(value);

  void _handleCommandResponse(List<int> value) {
    if (value.isEmpty) return;
    final int opcode = value[0];

    if (opcode == BleConstants.respSyncCheck || opcode == BleConstants.respSyncCheckLegacy) {
      final int count = value.length > 1 ? value[1] : 0;
      final c = _syncCheckCompleter;
      _syncCheckCompleter = null;
      if (c != null && !c.isCompleted) {
        if (count == 0 || value.length <= 2) {
          c.complete(<String>[]);
        } else {
          final payload = utf8.decode(value.sublist(2), allowMalformed: true);
          final files = payload
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          c.complete(files);
        }
      }
    } else if (opcode == BleConstants.respSyncChunk || opcode == BleConstants.respSyncChunkLegacy) {
      if (value.length < 4) {
        _chunkWatchdogTimer?.cancel();
        final c = _syncFileCompleter;
        _syncFileCompleter = null;
        if (c != null && !c.isCompleted) {
          c.complete(null);
        }
        return;
      }
      final int flags = value[3];
      if (flags == 0xFF) {
        // Error or file not found on SD
        _chunkWatchdogTimer?.cancel();
        final c = _syncFileCompleter;
        _syncFileCompleter = null;
        if (c != null && !c.isCompleted) {
          c.complete(null);
        }
        return;
      }

      // Reset inactivity watchdog on every valid chunk received
      _resetChunkWatchdog();

      if (value.length > 4) {
        _fileChunkBuffer.add(value.sublist(4));
        onSyncProgress?.call(_fileChunkBuffer.length);
      }

      if ((flags & 0x01) != 0) {
        // EOF reached
        _chunkWatchdogTimer?.cancel();
        final csv = utf8.decode(_fileChunkBuffer.takeBytes(), allowMalformed: true);
        final c = _syncFileCompleter;
        _syncFileCompleter = null;
        if (c != null && !c.isCompleted) {
          c.complete(csv);
        }
      }
    } else if (opcode == BleConstants.respSyncAck || opcode == BleConstants.respSyncAckLegacy) {
      final c = _syncAckCompleter;
      _syncAckCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete(true);
      }
    } else if (opcode == BleConstants.respDiagMode) {
      final bool active = value.length > 1 && value[1] != 0;
      final c = _diagModeCompleter;
      _diagModeCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete(active);
      }
    } else if (opcode == BleConstants.respDiagDtcList) {
      final int count = value.length > 1 ? value[1] : 0;
      final c = _diagDtcListCompleter;
      _diagDtcListCompleter = null;
      if (c != null && !c.isCompleted) {
        if (count == 0 || value.length <= 2) {
          c.complete(<DiagnosticTroubleCode>[]);
        } else {
          final payload = utf8.decode(value.sublist(2), allowMalformed: true);
          c.complete(DiagnosticTroubleCode.parseList(payload));
        }
      }
    } else if (opcode == BleConstants.respDiagClearAck) {
      final bool ok = value.length > 1 ? (value[1] != 0) : true;
      final c = _diagClearAckCompleter;
      _diagClearAckCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete(ok);
      }
    } else if (opcode == BleConstants.respCanRawFrame) {
      if (value.length >= 6 && !_rawCanFrameController.isClosed) {
        final byteData = ByteData.sublistView(Uint8List.fromList(value));
        final canId = byteData.getUint32(1, Endian.little);
        final dlc = value[5].clamp(0, 8);
        final data = <int>[];
        for (int i = 6; i < min(value.length, 6 + dlc); i++) {
          data.add(value[i]);
        }
        final frame = CapturedCanFrame(
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          canId: canId,
          data: data,
        );
        _rawCanFrameController.add(frame);
      }
    } else if (opcode == BleConstants.respOtaStatus) {
      if (value.length > 1) {
        _otaStateCode = value[1];
        _isOtaModeActive = (_otaStateCode == 1 || _otaStateCode == 2);
      }
      if (value.length >= 6) {
        _otaIpAddress = '${value[2]}.${value[3]}.${value[4]}.${value[5]}';
      }
      final c = _otaModeCompleter;
      _otaModeCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete(_otaStateCode != 4);
      }
    }
  }

  Future<void> _subscribeToTelemetry() async {
    if (_telemetryChar == null) return;

    try {
      await _telemetryChar!.setNotifyValue(true);
      await _notifySubscription?.cancel();
      _notifySubscription = _telemetryChar!.onValueReceived.listen((List<int> value) {
        if (value.isNotEmpty && !_telemetryController.isClosed) {
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

  Future<bool> sendCanProfileMode({required bool isCustomActive, int baudrateKbps = 500}) async {
    if (_mockMode) {
      debugPrint('[BLE MOCK] Set CAN profile mode to: $isCustomActive (Baud: $baudrateKbps kbps)');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      final bytes = [
        BleConstants.cmdSetCanProfileMode,
        isCustomActive ? 1 : 0,
        baudrateKbps & 0xFF,
        (baudrateKbps >> 8) & 0xFF,
      ];
      await _commandChar!.write(bytes, withoutResponse: true);
      debugPrint('[BLE] Sent CAN profile mode command: $isCustomActive ($baudrateKbps kbps)');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send CAN profile mode command: $e');
      return false;
    }
  }

  Future<bool> setCanSnifferMode(bool enable) async {
    _isCanSnifferActive = enable;
    if (_mockMode) {
      debugPrint('[BLE MOCK] Set CAN sniffer mode to: $enable');
      return true;
    }
    if (_commandChar == null) return false;

    try {
      final bytes = [BleConstants.cmdCanSnifferMode, enable ? 1 : 0];
      await _commandChar!.write(bytes, withoutResponse: true);
      debugPrint('[BLE] Sent CAN Sniffer Mode command: $enable');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to send CAN Sniffer Mode command: $e');
      return false;
    }
  }

  /// Enables or disables wireless Wi-Fi OTA firmware update mode on the ESP32-S3.
  /// When active, ESP32 launches SoftAP "MotoLogger-OTA" at http://192.168.4.1.
  Future<bool> setOtaMode(bool enable) async {
    if (_mockMode) {
      _isOtaModeActive = enable;
      _otaStateCode = enable ? 1 : 0;
      _otaIpAddress = '192.168.4.1';
      debugPrint('[BLE MOCK] Set OTA mode to: $enable');
      return true;
    }
    if (_commandChar == null) return false;

    final completer = Completer<bool>();
    try {
      _otaModeCompleter = completer;

      final bytes = [BleConstants.cmdOtaSetMode, enable ? 1 : 0];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent OTA mode command: $enable');

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          _isOtaModeActive = enable;
          return enable;
        },
      );
    } catch (e) {
      debugPrint('[BLE] setOtaMode error: $e');
      return false;
    } finally {
      if (_otaModeCompleter == completer) {
        _otaModeCompleter = null;
      }
    }
  }

  Future<bool> uploadBikeProfile(BikeProfile profile) async {
    if (profile.id == 'standard_obd2') {
      return await sendCanProfileMode(isCustomActive: false);
    }

    const disabledSlot = CanSignalMapping(
      key: 'disabled',
      canId: '0x000',
      startByte: 0,
      lengthBytes: 1,
    );

    bool success = true;
    success &= await sendCanSignalConfig(
      signalIndex: BleConstants.canSignalRpm,
      mapping: profile.rpmSignal ?? disabledSlot,
    );
    success &= await sendCanSignalConfig(
      signalIndex: BleConstants.canSignalSpeed,
      mapping: profile.speedSignal ?? disabledSlot,
    );
    success &= await sendCanSignalConfig(
      signalIndex: BleConstants.canSignalThrottle,
      mapping: profile.throttleSignal ?? disabledSlot,
    );
    success &= await sendCanSignalConfig(
      signalIndex: BleConstants.canSignalGear,
      mapping: profile.gearSignal ?? disabledSlot,
    );
    success &= await sendCanSignalConfig(
      signalIndex: BleConstants.canSignalCoolant,
      mapping: profile.coolantSignal ?? disabledSlot,
    );

    final baudKbps = (profile.canBaudrate ~/ 1000).clamp(250, 1000);
    success &= await sendCanProfileMode(isCustomActive: true, baudrateKbps: baudKbps);
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
        if (mockStationary || _mockDiagModeActive || _isOtaModeActive) {
          // Stationary workshop simulation (engine idling or off, bike on stand)
          final stationaryPacket = TelemetryPacket(
            timestampMs: (time * 1000).toInt(),
            leanAngleDeg: 0.2 * sin(time * 1.5),
            pitchDeg: 0.1 * cos(time * 1.5),
            accelXG: 0.01 * cos(time * 2.0),
            accelYG: 0.01 * sin(time * 2.0),
            accelZG: 1.0,
            gyroXDps: 0.0,
            gyroYDps: 0.0,
            gyroZDps: 0.0,
            engineRpm: _isOtaModeActive ? 0 : (1250 + (35 * sin(time * 3.0)).round()),
            vehicleSpeedKmh: 0,
            throttlePosPct: 0,
            coolantTempC: 88,
            gear: 0,
            batteryVoltage: 14.1,
            statusFlags: 0x1F, // SD OK, Engine Run, IMU OK
          );
          _telemetryController.add(stationaryPacket);
          return;
        }

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
          statusFlags: 0x0F, // SD OK, Engine Run, IMU OK (Listen-Only)
        );

        _telemetryController.add(mockPacket);
      });
    } else {
      _mockDiagModeActive = false;
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

  @visibleForTesting
  void emitMockTelemetryPacket(TelemetryPacket packet) {
    if (!_telemetryController.isClosed) {
      _telemetryController.add(packet);
    }
  }

  @visibleForTesting
  void setMockDtcList(List<DiagnosticTroubleCode> codes) {
    _mockDtcList
      ..clear()
      ..addAll(codes);
  }

  /// Enables or disables dedicated OBD-II Diagnostic Mode on the ESP32-S3.
  /// This is the ONLY mode in which the ESP32 transmits frames on the CAN bus.
  Future<bool> setDiagnosticMode(bool enable) async {
    if (_mockMode) {
      _mockDiagModeActive = enable;
      if (!_telemetryController.isClosed) {
        _telemetryController.add(TelemetryPacket(
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          leanAngleDeg: 0.0,
          pitchDeg: 0.0,
          accelXG: 0.0,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          engineRpm: enable ? 1250 : 0,
          vehicleSpeedKmh: 0,
          throttlePosPct: 0,
          coolantTempC: 88,
          gear: 0,
          batteryVoltage: 14.1,
          statusFlags: enable ? 0x1F : 0x0F,
        ));
      }
      debugPrint('[BLE MOCK] Diagnostic mode set to: $enable');
      return enable;
    }

    if (_commandChar == null) return false;

    final completer = Completer<bool>();
    try {
      if (_diagModeCompleter != null && !_diagModeCompleter!.isCompleted) {
        _diagModeCompleter!.complete(false);
      }
      _diagModeCompleter = completer;

      final bytes = [BleConstants.cmdDiagSetMode, enable ? 1 : 0];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent CMD_DIAG_SET_MODE: $enable');

      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => enable,
      );
    } catch (e) {
      debugPrint('[BLE] setDiagnosticMode error: $e');
      return false;
    } finally {
      if (_diagModeCompleter == completer) {
        _diagModeCompleter = null;
      }
    }
  }

  /// Requests an OBD-II Mode 03 (Stored) & Mode 07 (Pending) DTC scan from the ECU.
  Future<List<DiagnosticTroubleCode>> readDiagnosticTroubleCodes() async {
    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 120));
      return List<DiagnosticTroubleCode>.unmodifiable(_mockDtcList);
    }

    if (_commandChar == null) return const [];

    final completer = Completer<List<DiagnosticTroubleCode>>();
    try {
      if (_diagDtcListCompleter != null && !_diagDtcListCompleter!.isCompleted) {
        _diagDtcListCompleter!.complete(const []);
      }
      _diagDtcListCompleter = completer;

      final bytes = [BleConstants.cmdDiagReadDtc];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent CMD_DIAG_READ_DTC (Mode 03 & Mode 07 scan).');

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[BLE] readDiagnosticTroubleCodes timed out.');
          return const [];
        },
      );
    } catch (e) {
      debugPrint('[BLE] readDiagnosticTroubleCodes error: $e');
      return const [];
    } finally {
      if (_diagDtcListCompleter == completer) {
        _diagDtcListCompleter = null;
      }
    }
  }

  /// Requests OBD-II Mode 04 (Clear DTCs and reset MIL / Check Engine light).
  Future<bool> clearDiagnosticTroubleCodes() async {
    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 120));
      _mockDtcList.clear();
      debugPrint('[BLE MOCK] Cleared all OBD-II DTC fault codes.');
      return true;
    }

    if (_commandChar == null) return false;

    final completer = Completer<bool>();
    try {
      if (_diagClearAckCompleter != null && !_diagClearAckCompleter!.isCompleted) {
        _diagClearAckCompleter!.complete(false);
      }
      _diagClearAckCompleter = completer;

      final bytes = [BleConstants.cmdDiagClearDtc];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent CMD_DIAG_CLEAR_DTC (Mode 04 Clear).');

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[BLE] clearDiagnosticTroubleCodes error: $e');
      return false;
    } finally {
      if (_diagClearAckCompleter == completer) {
        _diagClearAckCompleter = null;
      }
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

    final completer = Completer<List<String>>();
    try {
      if (_syncCheckCompleter != null && !_syncCheckCompleter!.isCompleted) {
        _syncCheckCompleter!.complete([]);
      }
      _syncCheckCompleter = completer;

      final cmd = [BleConstants.cmdSyncCheck];
      await _commandChar!.write(cmd, withoutResponse: false);
      debugPrint('[BLE] Sent offline sync check command.');

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[BLE] checkOfflineLogs timed out.');
          return [];
        },
      );
    } catch (e) {
      debugPrint('[BLE] checkOfflineLogs error: $e');
      return [];
    } finally {
      if (_syncCheckCompleter == completer) {
        _syncCheckCompleter = null;
      }
    }
  }

  /// Downloads an offline session log by filename/id using a per-chunk inactivity watchdog
  Future<String?> downloadOfflineLog(String logId, {void Function(int bytesRead)? onProgress}) async {
    if (_mockMode) {
      if (_mockOfflineLogQueue.isNotEmpty) {
        final content = _mockOfflineLogQueue.first;
        onProgress?.call(content.length);
        return content;
      }
      return null;
    }

    if (_commandChar == null) return null;

    final completer = Completer<String?>();
    try {
      if (_syncFileCompleter != null && !_syncFileCompleter!.isCompleted) {
        _syncFileCompleter!.complete(null);
      }
      _fileChunkBuffer.clear();
      _syncFileCompleter = completer;
      onSyncProgress = onProgress;
      _resetChunkWatchdog();

      final bytes = [BleConstants.cmdSyncRequestFile, ...utf8.encode(logId)];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Requested log file download: $logId');

      return await completer.future;
    } catch (e) {
      debugPrint('[BLE] downloadOfflineLog error: $e');
      return null;
    } finally {
      _chunkWatchdogTimer?.cancel();
      onSyncProgress = null;
      if (_syncFileCompleter == completer) {
        _syncFileCompleter = null;
      }
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

    final completer = Completer<bool>();
    try {
      if (_syncAckCompleter != null && !_syncAckCompleter!.isCompleted) {
        _syncAckCompleter!.complete(false);
      }
      _syncAckCompleter = completer;

      final bytes = [BleConstants.cmdSyncAck, ...utf8.encode(logId)];
      await _commandChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Acknowledged offline log sync: $logId');

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => true,
      );
    } catch (e) {
      debugPrint('[BLE] acknowledgeOfflineLogSync error: $e');
      return false;
    } finally {
      if (_syncAckCompleter == completer) {
        _syncAckCompleter = null;
      }
    }
  }

  void disconnect() {
    _mockDiagModeActive = false;
    _mockTimer?.cancel();
    _scanTimeoutTimer?.cancel();
    _chunkWatchdogTimer?.cancel();
    for (final t in _mockScanTimers) {
      t.cancel();
    }
    _mockScanTimers.clear();
    _scanSubscription?.cancel();
    _discoveryScanSubscription?.cancel();
    _notifySubscription?.cancel();
    _commandSubscription?.cancel();
    _connectionSubscription?.cancel();
    if (_syncCheckCompleter != null && !_syncCheckCompleter!.isCompleted) {
      _syncCheckCompleter!.complete([]);
    }
    _syncCheckCompleter = null;
    if (_syncFileCompleter != null && !_syncFileCompleter!.isCompleted) {
      _syncFileCompleter!.complete(null);
    }
    _syncFileCompleter = null;
    if (_syncAckCompleter != null && !_syncAckCompleter!.isCompleted) {
      _syncAckCompleter!.complete(false);
    }
    _syncAckCompleter = null;
    if (_diagModeCompleter != null && !_diagModeCompleter!.isCompleted) {
      _diagModeCompleter!.complete(false);
    }
    _diagModeCompleter = null;
    if (_diagDtcListCompleter != null && !_diagDtcListCompleter!.isCompleted) {
      _diagDtcListCompleter!.complete(const []);
    }
    _diagDtcListCompleter = null;
    if (_diagClearAckCompleter != null && !_diagClearAckCompleter!.isCompleted) {
      _diagClearAckCompleter!.complete(false);
    }
    _diagClearAckCompleter = null;
    _isOtaModeActive = false;
    _otaStateCode = 0;
    if (_otaModeCompleter != null && !_otaModeCompleter!.isCompleted) {
      _otaModeCompleter!.complete(false);
    }
    _otaModeCompleter = null;
    _fileChunkBuffer.clear();
    _device?.disconnect();
    _setState(BleConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _telemetryController.close();
    _discoveredDevicesController.close();
    _rawCanFrameController.close();
  }
}
