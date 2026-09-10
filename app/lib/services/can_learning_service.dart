import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'ble_service.dart';
import 'gps_service.dart';

/// Represents a single recorded CAN frame during the learning session.
class CapturedCanFrame {
  final int timestampMs;
  final int canId;
  final List<int> data;

  const CapturedCanFrame({
    required this.timestampMs,
    required this.canId,
    required this.data,
  });

  String get hexId => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
  String get hexData => data.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
}

/// Synchronized ground-truth state point.
class LearningStatePoint {
  final int timestampMs;
  final double gpsSpeedKmh;
  final double accelXG;
  final double leanAngleDeg;
  final int observedRpm;
  final String phaseHint; // e.g. "IDLE", "REVVING", "MOVING", "BRAKING"

  const LearningStatePoint({
    required this.timestampMs,
    required this.gpsSpeedKmh,
    required this.accelXG,
    required this.leanAngleDeg,
    required this.observedRpm,
    required this.phaseHint,
  });
}

/// Service managing the motorcycle CAN learning and AI prompt generation flow.
class CanLearningService extends ChangeNotifier {
  final BleService bleService;
  final GpsService gpsService;

  bool _isRecording = false;
  int _recordingStartTimeMs = 0;
  int _elapsedSeconds = 0;
  Timer? _tickerTimer;
  Timer? _simulationTimer;

  final List<CapturedCanFrame> _capturedFrames = [];
  final List<LearningStatePoint> _statePoints = [];
  final Map<int, List<int>> _latestPayloadPerId = {};

  StreamSubscription? _bleSub;
  StreamSubscription? _gpsSub;

  double _currentGpsSpeed = 0.0;
  double _currentAccelX = 0.0;
  double _currentLean = 0.0;
  int _currentRpm = 0;

  bool get isRecording => _isRecording;
  int get elapsedSeconds => _elapsedSeconds;
  int get capturedFrameCount => _capturedFrames.length;
  int get uniqueCanIdCount => _latestPayloadPerId.length;
  bool get hasCompletedData => _capturedFrames.isNotEmpty;

  CanLearningService({
    required this.bleService,
    required this.gpsService,
  });

  void startRecording() {
    if (_isRecording) return;

    _isRecording = true;
    _recordingStartTimeMs = DateTime.now().millisecondsSinceEpoch;
    _elapsedSeconds = 0;
    _capturedFrames.clear();
    _statePoints.clear();
    _latestPayloadPerId.clear();

    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });

    _gpsSub = gpsService.positionStream.listen((pos) {
      _currentGpsSpeed = max(0.0, pos.speed * 3.6);
      notifyListeners();
    });

    _bleSub = bleService.telemetryStream.listen((packet) {
      _currentAccelX = packet.accelXG;
      _currentLean = packet.leanAngleDeg;
      _currentRpm = packet.engineRpm;

      _recordStatePoint();
      notifyListeners();
    });

    // If mock mode is active, simulate realistic motorcycle CAN bus traffic
    if (bleService.isMockMode) {
      _startMockCanTraffic();
    }

    notifyListeners();
  }

  void _recordStatePoint() {
    final nowMs = DateTime.now().millisecondsSinceEpoch - _recordingStartTimeMs;

    String phase = 'IDLE';
    if (_currentGpsSpeed < 3.0 && _currentRpm > 2500) {
      phase = 'REVVING_STANDSTILL';
    } else if (_currentGpsSpeed >= 3.0 && _currentAccelX > 0.1) {
      phase = 'ACCELERATION';
    } else if (_currentGpsSpeed >= 3.0 && _currentAccelX < -0.1) {
      phase = 'BRAKING';
    } else if (_currentGpsSpeed >= 3.0) {
      phase = 'CRUISE';
    }

    _statePoints.add(LearningStatePoint(
      timestampMs: nowMs,
      gpsSpeedKmh: _currentGpsSpeed,
      accelXG: _currentAccelX,
      leanAngleDeg: _currentLean,
      observedRpm: _currentRpm,
      phaseHint: phase,
    ));
  }

  /// Ingests a raw CAN frame into the learning dataset
  void ingestCanFrame(int canId, List<int> payload) {
    if (!_isRecording) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch - _recordingStartTimeMs;

    _capturedFrames.add(CapturedCanFrame(
      timestampMs: nowMs,
      canId: canId,
      data: List<int>.from(payload),
    ));
    _latestPayloadPerId[canId] = List<int>.from(payload);
  }

  void _startMockCanTraffic() {
    double time = 0.0;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isRecording) return;
      time += 0.05;

      final speed = (_currentGpsSpeed > 0 ? _currentGpsSpeed : 45.0 + 35.0 * sin(time * 0.5)).round();
      final rpm = (1800 + speed * 60 + 1200 * sin(time * 0.8).abs()).round().clamp(1200, 14000);
      final throttle = (sin(time * 0.6) > 0 ? (sin(time * 0.6) * 100).round() : 0).clamp(0, 100);
      final gear = speed < 5 ? 0 : (speed / 20).clamp(1, 6).toInt();
      final temp = 88;

      // 1. CAN ID 0x1F0: RPM (Bytes 0-1 Big Endian, 1:1), Speed (Bytes 2-3 Big Endian, 0.05 scale)
      final rawSpeed = (speed / 0.05).round();
      ingestCanFrame(0x1F0, [
        (rpm >> 8) & 0xFF,
        rpm & 0xFF,
        (rawSpeed >> 8) & 0xFF,
        rawSpeed & 0xFF,
        0x00,
        0x00,
        0x12,
        0x34,
      ]);

      // 2. CAN ID 0x208: Throttle (Byte 1, scale 2.55 = 0..255 for 0..100%), Gear (Byte 4)
      final rawTps = ((throttle * 255) / 100).round();
      ingestCanFrame(0x208, [
        0x01,
        rawTps & 0xFF,
        0x00,
        0x00,
        gear & 0xFF,
        0x55,
        0xAA,
        0x00,
      ]);

      // 3. CAN ID 0x280: Coolant Temp (Byte 0, offset -40)
      ingestCanFrame(0x280, [
        (temp + 40) & 0xFF,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
    });
  }

  /// Parses an existing MicroSD log file (LOG_XXXX.CSV) containing #CAN rows
  Future<int> importFromSdCsv(String csvContent) async {
    final lines = csvContent.split('\n');
    int count = 0;
    _capturedFrames.clear();
    _latestPayloadPerId.clear();
    _statePoints.clear();

    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#CAN,')) continue;

      final parts = trimmed.split(',');
      if (parts.length < 5) continue;

      try {
        final idStr = parts[2].trim().replaceAll('0x', '');
        final id = int.parse(idStr, radix: 16);
        final dlc = int.tryParse(parts[3].trim()) ?? 8;
        final payload = <int>[];

        for (int i = 4; i < min(parts.length, 4 + dlc); i++) {
          payload.add(int.parse(parts[i].trim(), radix: 16));
        }

        final ts = int.tryParse(parts[1].trim()) ?? (count * 10);

        _capturedFrames.add(CapturedCanFrame(
          timestampMs: ts ~/ 1000,
          canId: id,
          data: payload,
        ));
        _latestPayloadPerId[id] = payload;
        count++;
      } catch (_) {}
    }

    _elapsedSeconds = max(10, (_capturedFrames.length / 50).round());
    notifyListeners();
    return count;
  }

  void stopRecording() {
    if (!_isRecording) return;

    _isRecording = false;
    _tickerTimer?.cancel();
    _tickerTimer = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _bleSub?.cancel();
    _bleSub = null;
    _gpsSub?.cancel();
    _gpsSub = null;

    notifyListeners();
  }

  /// Generates the token-efficient dataset JSON for the AI model
  Map<String, dynamic> generateDatasetSummary() {
    // 1. Group frames by CAN ID
    final Map<int, List<CapturedCanFrame>> byId = {};
    for (final f in _capturedFrames) {
      byId.putIfAbsent(f.canId, () => []).add(f);
    }

    // 2. Compute statistics for each CAN ID
    final List<Map<String, dynamic>> canIdSummaries = [];
    byId.forEach((id, frames) {
      final hexId = '0x${id.toRadixString(16).toUpperCase().padLeft(3, '0')}';
      final count = frames.length;

      // Analyze byte variation across the frames
      final minBytes = List.filled(8, 255);
      final maxBytes = List.filled(8, 0);
      final changedBytes = <int>{};

      for (final f in frames) {
        for (int i = 0; i < min(8, f.data.length); i++) {
          final b = f.data[i];
          if (b < minBytes[i]) minBytes[i] = b;
          if (b > maxBytes[i]) maxBytes[i] = b;
        }
      }

      for (int i = 0; i < 8; i++) {
        if (minBytes[i] != maxBytes[i]) {
          changedBytes.add(i);
        }
      }

      // Pick representative payload samples
      final samples = <String>[];
      final step = max(1, (frames.length / 4).floor());
      for (int i = 0; i < frames.length; i += step) {
        samples.add(frames[i].hexData);
        if (samples.length >= 4) break;
      }

      canIdSummaries.add({
        'can_id': hexId,
        'message_count': count,
        'varying_byte_indices': changedBytes.toList()..sort(),
        'min_bytes_hex': minBytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).toList(),
        'max_bytes_hex': maxBytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).toList(),
        'sample_payloads': samples,
      });
    });

    // 3. Extract key correlated ground-truth timeline snapshots
    final timelineSnapshots = <Map<String, dynamic>>[];
    final durationMs = _elapsedSeconds * 1000;
    final snapshotTimes = [
      (durationMs * 0.1).round(),
      (durationMs * 0.3).round(),
      (durationMs * 0.5).round(),
      (durationMs * 0.7).round(),
      (durationMs * 0.9).round(),
    ];

    for (final targetTs in snapshotTimes) {
      // Find closest state point
      LearningStatePoint? bestState;
      int minDiff = 999999999;
      for (final s in _statePoints) {
        final diff = (s.timestampMs - targetTs).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestState = s;
        }
      }

      // Find closest CAN frames near this timestamp
      final framesAtTs = <String, String>{};
      for (final id in byId.keys) {
        final frames = byId[id]!;
        CapturedCanFrame? bestFrame;
        int frameMinDiff = 999999999;
        for (final f in frames) {
          final diff = (f.timestampMs - targetTs).abs();
          if (diff < frameMinDiff) {
            frameMinDiff = diff;
            bestFrame = f;
          }
        }
        if (bestFrame != null) {
          framesAtTs[bestFrame.hexId] = bestFrame.hexData;
        }
      }

      timelineSnapshots.add({
        'time_ms': targetTs,
        'ground_truth': {
          'phase': bestState?.phaseHint ?? 'UNKNOWN',
          'gps_speed_kmh': bestState != null ? double.parse(bestState.gpsSpeedKmh.toStringAsFixed(1)) : 0.0,
          'accel_x_g': bestState != null ? double.parse(bestState.accelXG.toStringAsFixed(2)) : 0.0,
          'lean_angle_deg': bestState != null ? double.parse(bestState.leanAngleDeg.toStringAsFixed(1)) : 0.0,
        },
        'can_bus_frames': framesAtTs,
      });
    }

    return {
      'tool': 'MotoLogger AI CAN Profiler',
      'version': '1.0',
      'session_duration_seconds': _elapsedSeconds,
      'total_can_frames_captured': _capturedFrames.length,
      'unique_can_ids_detected': canIdSummaries.length,
      'can_bus_baudrate_tested': 500000,
      'can_id_analysis': canIdSummaries,
      'correlated_timeline_snapshots': timelineSnapshots,
    };
  }

  /// System prompt formatted specifically for LLM reverse engineering
  String generateAiPrompt() {
    return '''You are an expert motorcycle telemetry engineer and automotive CAN bus reverse-engineering specialist.

Task:
Analyze the attached MotoLogger telemetry and CAN bus dataset. The user performed a calibration test ride with synchronized GPS speed, acceleration, and CAN bus traffic.
Identify the CAN message IDs, byte positions, endianness, multipliers, and offsets for the following vehicle signals:
1. "engine_rpm": Engine speed (RPM, ~1000 - 15000)
2. "vehicle_speed": Motorcycle speed (km/h, correlating with GPS speed)
3. "throttle_pos": Throttle position / TPS (0 - 100 %)
4. "gear": Engaged gear (-1 = unknown, 0 = N, 1..6)
5. "coolant_temp": Engine coolant temperature (°C, typically 70 - 105 °C, often offset by -40)

Response Requirements:
Output ONLY a valid JSON object matching the exact schema below.
DO NOT include conversational text, pleasantries, or markdown formatting other than the JSON object itself.

Required JSON Output Schema:
{
  "bike_name": "<Motorcycle Model Name guessed or 'Custom Bike'>",
  "can_bus_baudrate": 500000,
  "signals": {
    "engine_rpm": {
      "can_id": "0x...",
      "start_byte": 0,
      "length_bytes": 2,
      "endianness": "big",
      "multiplier": 1.0,
      "offset": 0.0,
      "unit": "RPM"
    },
    "vehicle_speed": {
      "can_id": "0x...",
      "start_byte": 2,
      "length_bytes": 2,
      "endianness": "big",
      "multiplier": 0.05,
      "offset": 0.0,
      "unit": "km/h"
    },
    "throttle_pos": {
      "can_id": "0x...",
      "start_byte": 1,
      "length_bytes": 1,
      "endianness": "little",
      "multiplier": 0.392,
      "offset": 0.0,
      "unit": "%"
    },
    "gear": {
      "can_id": "0x...",
      "start_byte": 4,
      "length_bytes": 1,
      "endianness": "little",
      "multiplier": 1.0,
      "offset": 0.0,
      "unit": "gear"
    },
    "coolant_temp": {
      "can_id": "0x...",
      "start_byte": 0,
      "length_bytes": 1,
      "endianness": "little",
      "multiplier": 1.0,
      "offset": -40.0,
      "unit": "°C"
    }
  }
}''';
  }

  /// Writes dataset to local temporary file and invokes system Share sheet
  Future<void> shareDatasetFile() async {
    final data = generateDatasetSummary();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/motologger_can_dataset.json');
    await file.writeAsString(jsonStr);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'MotoLogger CAN Bus Dataset for AI Analysis',
      text: 'Synchronized motorcycle CAN bus data for AI reverse-engineering.',
    );
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _simulationTimer?.cancel();
    _bleSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}
