import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants/ble_constants.dart';
import '../models/telemetry_packet.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error
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

  StreamSubscription? _scanSubscription;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _mockTimer;
  bool _mockMode = false;

  void _setState(BleConnectionState newState) {
    _state = newState;
    _stateController.add(_state);
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
          if (r.device.platformName == BleConstants.deviceName ||
              r.advertisementData.serviceUuids.contains(Guid(BleConstants.serviceUuid))) {
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
      _setState(BleConnectionState.disconnected);
    }
  }

  void disconnect() {
    _mockTimer?.cancel();
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    _device?.disconnect();
    _setState(BleConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _telemetryController.close();
  }
}
