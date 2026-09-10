import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/telemetry_packet.dart';
import '../models/fused_sample.dart';
import '../models/session.dart';
import 'ble_service.dart';
import 'gps_service.dart';
import 'database_service.dart';
import 'can_profile_service.dart';

class TelemetryManager extends ChangeNotifier {
  final BleService bleService;
  final GpsService gpsService;
  final DatabaseService dbService;
  final CanProfileService canProfileService;

  TelemetryPacket _latestPacket = TelemetryPacket.initial();
  Position? _latestPosition;

  bool _isRecording = false;
  bool _isPaused = false;
  int? _currentSessionId;
  String _sessionTitle = 'Track Ride';
  DateTime? _sessionStartTime;

  double _maxLeanLeft = 0.0;
  double _maxLeanRight = 0.0;
  double _topSpeed = 0.0;
  double _maxG = 0.0;
  double _totalDistanceKm = 0.0;
  int _sampleCount = 0;
  double _mountingRollOffsetDeg = 0.0;
  double _latestRawLeanDeg = 0.0;

  // Polar friction envelope: 36 angular sectors (every 10 deg)
  final List<double> _frictionEnvelope = List.filled(36, 0.15);

  final List<FusedSample> _sampleBuffer = [];
  Timer? _batchFlushTimer;
  StreamSubscription? _bleSub;
  StreamSubscription? _bleStateSub;
  StreamSubscription? _gpsSub;

  TelemetryPacket get latestPacket => _latestPacket;
  Position? get latestPosition => _latestPosition;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  double get maxLeanLeft => _maxLeanLeft;
  double get maxLeanRight => _maxLeanRight;
  double get topSpeed => _topSpeed;
  double get maxG => _maxG;
  double get totalDistanceKm => _totalDistanceKm;
  int get sampleCount => _sampleCount;
  double get mountingRollOffsetDeg => _mountingRollOffsetDeg;
  double get latestRawLeanDeg => _latestRawLeanDeg;
  List<double> get frictionEnvelopeRadii => List.unmodifiable(_frictionEnvelope);

  TelemetryManager({
    required this.bleService,
    required this.gpsService,
    required this.dbService,
    CanProfileService? canProfileService,
  }) : canProfileService = canProfileService ?? CanProfileService(dbService: dbService) {
    _initListeners();
    _loadSavedMountingOffset();
  }

  Future<void> _loadSavedMountingOffset() async {
    try {
      final saved = await dbService.getSetting('mounting_roll_offset');
      if (saved != null) {
        _mountingRollOffsetDeg = double.tryParse(saved) ?? 0.0;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _initListeners() {
    _bleStateSub = bleService.stateStream.listen((state) {
      if (state == BleConnectionState.connected && _mountingRollOffsetDeg != 0.0) {
        bleService.sendTareOffset(_mountingRollOffsetDeg);
      }
      notifyListeners();
    });

    _bleSub = bleService.telemetryStream.listen((packet) {
      _latestRawLeanDeg = packet.leanAngleDeg;

      // Apply calibrated mounting offset
      final calibratedRoll = packet.leanAngleDeg - _mountingRollOffsetDeg;
      final adjustedPacket = packet.copyWith(leanAngleDeg: calibratedRoll);
      _latestPacket = adjustedPacket;

      // Update real-time peak dynamics
      if (adjustedPacket.leanAngleDeg < _maxLeanLeft) {
        _maxLeanLeft = adjustedPacket.leanAngleDeg;
      }
      if (adjustedPacket.leanAngleDeg > _maxLeanRight) {
        _maxLeanRight = adjustedPacket.leanAngleDeg;
      }
      if (adjustedPacket.vehicleSpeedKmh > _topSpeed) {
        _topSpeed = adjustedPacket.vehicleSpeedKmh.toDouble();
      }

      final currentG = sqrt(adjustedPacket.accelXG * adjustedPacket.accelXG + adjustedPacket.accelYG * adjustedPacket.accelYG);
      if (currentG > _maxG) {
        _maxG = currentG;
      }

      // Update polar friction envelope for G-G diagram
      if (currentG > 0.05) {
        double angle = atan2(adjustedPacket.accelYG, adjustedPacket.accelXG);
        if (angle < 0) angle += 2 * pi;
        final sector = ((angle / (2 * pi)) * 36).floor() % 36;
        if (currentG > _frictionEnvelope[sector]) {
          _frictionEnvelope[sector] = currentG;
        }
      }

      // If session recording is active and not paused, fuse with GPS and buffer
      if (_isRecording && !_isPaused && _currentSessionId != null) {
        _sampleCount++;
        final sample = FusedSample.fromTelemetryAndGps(
          sessionId: _currentSessionId!,
          packet: adjustedPacket,
          latitude: _latestPosition?.latitude ?? 0.0,
          longitude: _latestPosition?.longitude ?? 0.0,
          altitude: _latestPosition?.altitude ?? 0.0,
          gpsSpeedKmh: _latestPosition != null ? (_latestPosition!.speed * 3.6) : 0.0,
          bearing: _latestPosition?.heading ?? 0.0,
          gpsAccuracyMeters: _latestPosition?.accuracy ?? 0.0,
        );

        _sampleBuffer.add(sample);

        // Flush buffer if 50 samples accumulated (~2 seconds of data)
        if (_sampleBuffer.length >= 50) {
          _flushBuffer();
        }
      }

      notifyListeners();
    });

    _gpsSub = gpsService.positionStream.listen((pos) {
      if (_latestPosition != null && _isRecording && !_isPaused) {
        final distanceMeters = Geolocator.distanceBetween(
          _latestPosition!.latitude,
          _latestPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        _totalDistanceKm += (distanceMeters / 1000.0);
      }
      _latestPosition = pos;
      notifyListeners();
    });

    // Periodic flush timer (every 2 seconds)
    _batchFlushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_sampleBuffer.isNotEmpty) {
        _flushBuffer();
      }
    });
  }

  Future<void> startRecording([String? title]) async {
    if (_isRecording) return;

    _sessionTitle = title ?? 'Ride ${DateTime.now().toLocal().toString().substring(0, 16)}';
    _sessionStartTime = DateTime.now();
    _maxLeanLeft = 0.0;
    _maxLeanRight = 0.0;
    _topSpeed = 0.0;
    _maxG = 0.0;
    _totalDistanceKm = 0.0;
    _sampleCount = 0;
    _sampleBuffer.clear();
    _isPaused = false;
    _frictionEnvelope.fillRange(0, 36, 0.15);

    _currentSessionId = await dbService.startSession(_sessionTitle);
    _isRecording = true;
    notifyListeners();
  }

  void pauseRecording() {
    if (_isRecording && !_isPaused) {
      _isPaused = true;
      notifyListeners();
    }
  }

  void resumeRecording() {
    if (_isRecording && _isPaused) {
      _isPaused = false;
      notifyListeners();
    }
  }

  void resetPeaks() {
    _maxLeanLeft = 0.0;
    _maxLeanRight = 0.0;
    _topSpeed = 0.0;
    _maxG = 0.0;
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (!_isRecording || _currentSessionId == null) return;

    await _flushBuffer();

    final session = RideSession(
      id: _currentSessionId,
      title: _sessionTitle,
      startTime: _sessionStartTime ?? DateTime.now(),
      endTime: DateTime.now(),
      maxLeanLeftDeg: _maxLeanLeft,
      maxLeanRightDeg: _maxLeanRight,
      topSpeedKmh: _topSpeed,
      maxGForce: _maxG,
      totalDistanceKm: _totalDistanceKm,
      sampleCount: _sampleCount,
    );

    await dbService.updateSession(session);

    _isRecording = false;
    _isPaused = false;
    _currentSessionId = null;
    notifyListeners();
  }

  Future<void> _flushBuffer() async {
    if (_sampleBuffer.isEmpty) return;
    final toWrite = List<FusedSample>.from(_sampleBuffer);
    _sampleBuffer.clear();
    await dbService.insertSampleBatch(toWrite);
  }

  Future<void> _applyMountingOffset(double offsetDeg) async {
    _mountingRollOffsetDeg = offsetDeg;

    // Persist to local SQLite database
    await dbService.saveSetting('mounting_roll_offset', _mountingRollOffsetDeg.toStringAsFixed(2));

    // Send offset to ESP unit via BLE
    await bleService.sendTareOffset(_mountingRollOffsetDeg);

    // Immediately update latest packet with calibrated offset
    final calibratedRoll = _latestRawLeanDeg - _mountingRollOffsetDeg;
    _latestPacket = _latestPacket.copyWith(leanAngleDeg: calibratedRoll);

    resetPeaks();
    notifyListeners();
  }

  /// Unified calibration method:
  /// Sets mounting offset such that: (calibratedRoll == targetAngleDeg)
  /// [targetAngleDeg] is the real motorcycle lean angle:
  /// - For side-stand calibration: angle measured by smartphone on tank cap.
  /// - For upright calibration: 0.0° (vertical).
  Future<void> calibrateMountingOffset({required double targetAngleDeg}) async {
    final offset = _latestRawLeanDeg - targetAngleDeg;
    await _applyMountingOffset(offset);
  }

  /// Calibrate mounting zero offset using the smartphone placed flat on fuel tank cap
  /// [phoneRollDeg] is the real motorcycle tilt angle on the side stand measured by the phone.
  Future<void> calibrateFromTank({required double phoneRollDeg}) async {
    await calibrateMountingOffset(targetAngleDeg: phoneRollDeg);
  }

  /// Calibrate mounting zero offset with motorcycle held upright (0.0°)
  Future<void> calibrateUpright() async {
    await calibrateMountingOffset(targetAngleDeg: 0.0);
    await bleService.sendTareZero();
  }

  /// Backward compatible alias for upright tare
  Future<void> tareZero() async {
    await calibrateUpright();
  }

  /// Reset mounting offset back to factory default 0.0°
  Future<void> resetMountingOffset() async {
    await _applyMountingOffset(0.0);
    await bleService.sendTareZero();
  }

  void resetFrictionEnvelope() {
    _frictionEnvelope.fillRange(0, 36, 0.15);
    notifyListeners();
  }

  @override
  void dispose() {
    _batchFlushTimer?.cancel();
    _bleSub?.cancel();
    _bleStateSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}
