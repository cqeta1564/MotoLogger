import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/telemetry_packet.dart';
import '../models/fused_sample.dart';
import '../models/session.dart';
import '../models/dtc_code.dart';
import '../models/lap_split.dart';
import 'ble_service.dart';
import 'gps_service.dart';
import 'database_service.dart';
import 'can_profile_service.dart';
import 'lap_timer_service.dart';

class TelemetryManager extends ChangeNotifier {
  final BleService bleService;
  final GpsService gpsService;
  final DatabaseService dbService;
  final CanProfileService canProfileService;

  static const MethodChannel _carChannel =
      MethodChannel('com.motologger.app/car_projection');
  int _lastCarUpdateTime = 0;

  TelemetryPacket _latestPacket = TelemetryPacket.initial();
  Position? _latestPosition;

  // Live Lap Timing & Custom Circuit
  TrackCircuit? _activeCircuit;
  final List<LapSplit> _liveLaps = [];
  int _currentLapNumber = 1;
  Duration? _currentLapElapsed;
  double? _lastLapDeltaSeconds;
  DateTime? _currentLapStartTime;
  int _lastCrossingMs = -999999;
  FusedSample? _lastFusedSample;

  TrackCircuit? get activeCircuit => _activeCircuit;
  List<LapSplit> get liveLaps => List.unmodifiable(_liveLaps);
  int get currentLapNumber => _currentLapNumber;
  Duration? get currentLapElapsed => _currentLapElapsed;
  double? get lastLapDeltaSeconds => _lastLapDeltaSeconds;

  bool _isRecording = false;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<void>? _flushing;
  String? _recordingError;
  String? get recordingError => _recordingError;
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
  Timer? _syncStatusClearTimer;
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
  DateTime? get sessionStartTime => _sessionStartTime;
  Duration get currentRideDuration =>
      _sessionStartTime != null && _isRecording
          ? DateTime.now().difference(_sessionStartTime!)
          : Duration.zero;
  List<double> get frictionEnvelopeRadii =>
      List.unmodifiable(_frictionEnvelope);

  // Automatic offline sync state
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String? _syncStatusMessage;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String? get syncStatusMessage => _syncStatusMessage;

  // Dedicated OBD-II Diagnostic Mode state (ONLY mode with active CAN TX)
  bool _isDiagnosticModeActive = false;
  bool _isScanningDtc = false;
  bool _isClearingDtc = false;
  List<DiagnosticTroubleCode> _diagnosticTroubleCodes = const [];
  DateTime? _lastDtcScanTime;
  String? _diagnosticStatusMessage;

  bool get isDiagnosticModeActive =>
      _isDiagnosticModeActive || _latestPacket.isDiagnosticModeActive;
  bool get isScanningDtc => _isScanningDtc;
  bool get isClearingDtc => _isClearingDtc;
  List<DiagnosticTroubleCode> get diagnosticTroubleCodes =>
      List.unmodifiable(_diagnosticTroubleCodes);
  DateTime? get lastDtcScanTime => _lastDtcScanTime;
  String? get diagnosticStatusMessage => _diagnosticStatusMessage;

  double get currentEffectiveSpeedKmh {
    final gpsSpeedKmh = (_latestPosition != null && _latestPosition!.speed > 0)
        ? (_latestPosition!.speed * 3.6)
        : 0.0;
    return _latestPacket.vehicleSpeedKmh > 0
        ? _latestPacket.vehicleSpeedKmh.toDouble()
        : gpsSpeedKmh;
  }

  bool get isSimulationMode => bleService.isMockMode || gpsService.isMockMode;

  void setSimulationMode(bool enable) {
    if (_isRecording || _starting != null) return;
    if (!enable) {
      _isDiagnosticModeActive = false;
      _diagnosticStatusMessage = null;
    }
    bleService.enableMockMode(enable);
    gpsService.enableMockMode(enable);
    if (!enable) {
      resetPeaks();
    }
    notifyListeners();
  }

  TelemetryManager({
    required this.bleService,
    required this.gpsService,
    required this.dbService,
    CanProfileService? canProfileService,
  }) : canProfileService =
            canProfileService ?? CanProfileService(dbService: dbService) {
    _initListeners();
    _loadSavedMountingOffset();
    _initPairedDevice();
    _carChannel.setMethodCallHandler((call) async {
      if (call.method == 'tareZero') {
        await tareZero();
      }
    });
  }

  Future<void> _initPairedDevice() async {
    await bleService.initPairedDevice(dbService: dbService);
    notifyListeners();
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
      if (state == BleConnectionState.connected) {
        if (_mountingRollOffsetDeg != 0.0) {
          bleService.sendTareOffset(_mountingRollOffsetDeg);
        }
        if (canProfileService.isCustomProfileActive) {
          bleService.uploadBikeProfile(canProfileService.activeProfile);
        }
        // Automatically check and synchronize any offline sessions from ESP32 MicroSD
        autoSyncOfflineSessions();
      } else {
        _isDiagnosticModeActive = false;
        _sendCarTelemetry(_latestPacket, 0.0, force: true);
      }
      notifyListeners();
    });

    _bleSub = bleService.telemetryStream.listen((packet) {
      final double calibratedRoll;
      if (bleService.isMockMode) {
        _latestRawLeanDeg = packet.leanAngleDeg;
        calibratedRoll = packet.leanAngleDeg - _mountingRollOffsetDeg;
      } else {
        // Real ESP32 firmware already subtracts _mountingRollOffsetDeg before transmitting.
        // Reconstruct uncalibrated raw IMU roll so repeated calibrations remain idempotent.
        calibratedRoll = packet.leanAngleDeg;
        _latestRawLeanDeg = packet.leanAngleDeg + _mountingRollOffsetDeg;
      }
      final adjustedPacket = packet.copyWith(leanAngleDeg: calibratedRoll);
      _latestPacket = adjustedPacket;

      // Update real-time peak dynamics
      if (adjustedPacket.leanAngleDeg < _maxLeanLeft) {
        _maxLeanLeft = adjustedPacket.leanAngleDeg;
      }
      if (adjustedPacket.leanAngleDeg > _maxLeanRight) {
        _maxLeanRight = adjustedPacket.leanAngleDeg;
      }
      final gpsSpeedKmh = (_latestPosition != null && _latestPosition!.speed > 0)
          ? (_latestPosition!.speed * 3.6)
          : 0.0;
      final effectiveSpeedKmh = adjustedPacket.vehicleSpeedKmh > 0
          ? adjustedPacket.vehicleSpeedKmh.toDouble()
          : gpsSpeedKmh;
      if (effectiveSpeedKmh > _topSpeed) {
        _topSpeed = effectiveSpeedKmh;
      }

      // Stream updates to Android Auto head unit (~5 Hz throttle)
      _sendCarTelemetry(adjustedPacket, effectiveSpeedKmh);

      // Safety interlock: if Diagnostic Mode is active and motorcycle starts moving (> 5 km/h),
      // immediately disable active CAN transmission and return to Listen-Only passive mode.
      final bool movingAboveSafetyLimit = adjustedPacket.vehicleSpeedKmh > 5 ||
          (!isSimulationMode && effectiveSpeedKmh > 5.0);
      if (isDiagnosticModeActive && movingAboveSafetyLimit) {
        _isDiagnosticModeActive = false;
        _diagnosticStatusMessage =
            'Diagnostika byla automaticky ukončena (detekován pohyb > 5 km/h). Jednotka přešla do pasivního režimu.';
        bleService.setDiagnosticMode(false);
      } else {
        _isDiagnosticModeActive = adjustedPacket.isDiagnosticModeActive;
      }

      final currentG = sqrt(adjustedPacket.accelXG * adjustedPacket.accelXG +
          adjustedPacket.accelYG * adjustedPacket.accelYG);
      if (currentG > _maxG) {
        _maxG = currentG;
      }

      // Update polar friction envelope for G-G diagram
      // Horizontal axis in GgFrictionReticle is lateral G (accelYG),
      // Vertical axis is longitudinal G (accelXG).
      if (currentG > 0.05) {
        double angle = atan2(adjustedPacket.accelXG, adjustedPacket.accelYG);
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
          gpsSpeedKmh:
              _latestPosition != null ? (_latestPosition!.speed * 3.6) : 0.0,
          bearing: _latestPosition?.heading ?? 0.0,
          gpsAccuracyMeters: _latestPosition?.accuracy ?? 0.0,
        );

        _sampleBuffer.add(sample);

        if (_currentLapStartTime != null) {
          _currentLapElapsed = DateTime.now().difference(_currentLapStartTime!);
        }

        // Auto-detect circuit if not set and rider is near known circuit
        if (_activeCircuit == null && _latestPosition != null) {
          for (final circuit in LapTimerService.knownCircuits) {
            final dist = Geolocator.distanceBetween(
              _latestPosition!.latitude,
              _latestPosition!.longitude,
              circuit.centerLat,
              circuit.centerLon,
            );
            if (dist <= 500.0) {
              _activeCircuit = circuit;
              _currentLapStartTime ??= DateTime.now();
              break;
            }
          }
        }

        // Live lap crossing detection
        if (_activeCircuit != null && _lastFusedSample != null) {
          final crossing = LapTimerService.checkSingleSegmentCrossing(
            _lastFusedSample!,
            sample,
            _activeCircuit!,
            lastCrossMs: _lastCrossingMs,
          );
          if (crossing != null) {
            if (_lastCrossingMs > 0) {
              final lapTimeMs = crossing.timestampMs - _lastCrossingMs;
              final isBest = _liveLaps.isEmpty ||
                  lapTimeMs <
                      _liveLaps.map((l) => l.lapTimeMs).reduce(min);
              final deltaMs = _liveLaps.isEmpty
                  ? 0
                  : lapTimeMs -
                      _liveLaps.map((l) => l.lapTimeMs).reduce(min);
              _lastLapDeltaSeconds =
                  _liveLaps.isEmpty ? null : deltaMs / 1000.0;

              _liveLaps.add(LapSplit(
                lapNumber: _currentLapNumber,
                lapTime: Duration(milliseconds: lapTimeMs),
                lapTimeMs: lapTimeMs,
                startTimestampMs: _lastCrossingMs,
                endTimestampMs: crossing.timestampMs,
                startSampleIndex: 0,
                endSampleIndex: _sampleCount,
                topSpeedKmh: sample.gpsSpeedKmh,
                maxLeanLeftDeg: _maxLeanLeft,
                maxLeanRightDeg: _maxLeanRight,
                maxGForce: _maxG,
                deltaToBest: Duration(milliseconds: deltaMs.abs()),
                deltaMs: deltaMs,
                isBestLap: isBest,
              ));
              _currentLapNumber++;
            }
            _lastCrossingMs = crossing.timestampMs;
            _currentLapStartTime = DateTime.now();
          }
        }
        _lastFusedSample = sample;

        // Flush buffer if 50 samples accumulated (~2 seconds of data)
        if (_sampleBuffer.length >= 50) {
          _flushSafely();
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
        _flushSafely();
      }
    });
  }

  Future<void> startRecording([String? title]) {
    if (_isRecording) return Future.value();
    return _starting ??=
        _startRecording(title).whenComplete(() => _starting = null);
  }

  Future<void> _startRecording(String? title) async {
    if (_isRecording) return;

    // Safety interlock: ensure active OBD-II CAN transmission is disabled before riding
    if (isDiagnosticModeActive) {
      await setDiagnosticMode(false);
    }

    _recordingError = null;
    _sessionTitle =
        title ?? 'Ride ${DateTime.now().toLocal().toString().substring(0, 16)}';
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
    _liveLaps.clear();
    _currentLapNumber = 1;
    _lastLapDeltaSeconds = null;
    _currentLapStartTime = DateTime.now();
    _lastCrossingMs = -999999;
    _lastFusedSample = null;
    _currentLapElapsed = null;

    if (_latestPosition != null) {
      for (final circuit in LapTimerService.knownCircuits) {
        final dist = Geolocator.distanceBetween(
          _latestPosition!.latitude,
          _latestPosition!.longitude,
          circuit.centerLat,
          circuit.centerLon,
        );
        if (dist <= 500.0) {
          _activeCircuit = circuit;
          break;
        }
      }
    }

    notifyListeners();
  }

  /// Sets a custom finish line gate at the current GPS position and heading
  void markCustomFinishLineHere() {
    final pos = _latestPosition;
    if (pos == null) return;
    double heading = pos.heading;
    if (heading == 0.0 && _lastFusedSample != null) {
      final b = Geolocator.bearingBetween(
        _lastFusedSample!.latitude,
        _lastFusedSample!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (!b.isNaN) {
        heading = (b + 360.0) % 360.0;
      }
    }
    _activeCircuit = LapTimerService.createCustomCircuitFromPosition(
      lat: pos.latitude,
      lon: pos.longitude,
      headingDeg: heading,
      name: 'Vlastní cíl',
    );
    _currentLapNumber = 1;
    _currentLapStartTime = DateTime.now();
    // Use packet monotonic timestamp domain to match FusedSample.timestampMs
    _lastCrossingMs =
        _latestPacket.timestampMs > 0 ? _latestPacket.timestampMs : 0;
    _liveLaps.clear();
    _lastLapDeltaSeconds = null;
    notifyListeners();
  }

  void _sendCarTelemetry(TelemetryPacket packet, double speedKmh,
      {bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastCarUpdateTime < 200) return; // 5 Hz throttle
    _lastCarUpdateTime = now;

    final data = <String, dynamic>{
      'leanAngleDeg': packet.leanAngleDeg,
      'speedKmh': speedKmh.round(),
      'engineRpm': packet.engineRpm,
      'gear': packet.gear,
      'coolantTempC': packet.coolantTempC,
      'accelXG': packet.accelXG,
      'accelYG': packet.accelYG,
      'maxLeanLeft': _maxLeanLeft,
      'maxLeanRight': _maxLeanRight,
      'isConnected':
          bleService.state == BleConnectionState.connected || bleService.isMockMode,
      'isRecording': _isRecording,
      'currentLap': _currentLapNumber,
      'lapElapsedMs': _currentLapElapsed?.inMilliseconds ?? 0,
      'deltaSeconds': _lastLapDeltaSeconds,
    };
    _carChannel.invokeMethod('updateTelemetry', data).catchError((_) {});
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

  Future<void> stopRecording() {
    return _stopping ??= _stopRecording().whenComplete(() => _stopping = null);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _currentSessionId == null) return;

    // Freeze incoming samples while saving. A failure leaves a retryable ride.
    _isPaused = true;
    notifyListeners();
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
    _recordingError = null;
    _isPaused = false;
    _currentSessionId = null;
    notifyListeners();
  }

  Future<void> _flushSafely() async {
    try {
      await _flushBuffer();
    } catch (_) {
      _isPaused = true;
      _recordingError =
          'Zápis do telefonu se nezdařil. Uvolněte místo a uložte jízdu znovu.';
      notifyListeners();
    }
  }

  Future<void> _flushBuffer() {
    return _flushing ??= _writeBuffer().whenComplete(() => _flushing = null);
  }

  Future<void> _writeBuffer() async {
    // Retain samples until SQLite acknowledges them. Serialize concurrent flushes.
    while (_sampleBuffer.isNotEmpty) {
      final toWrite = List<FusedSample>.from(_sampleBuffer);
      await dbService.insertSampleBatch(toWrite);
      _sampleBuffer.removeRange(0, toWrite.length);
    }
    _recordingError = null;
  }

  Future<void> _applyMountingOffset(double offsetDeg) async {
    if (!await bleService.sendTareOffset(offsetDeg)) {
      throw StateError('Calibration command could not be sent');
    }
    await dbService.saveSetting(
        'mounting_roll_offset', offsetDeg.toStringAsFixed(2));
    _mountingRollOffsetDeg = offsetDeg;

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

  /// Sync active motorcycle CAN profile to ESP32 unit over BLE
  Future<bool> syncActiveProfileToEsp() async {
    final success =
        await bleService.uploadBikeProfile(canProfileService.activeProfile);
    notifyListeners();
    return success;
  }

  // Paired ESP hardware management
  String? get pairedDeviceId => bleService.pairedDeviceId;
  String? get pairedDeviceName => bleService.pairedDeviceName;
  bool get isPaired => bleService.isPaired;

  Future<bool> pairDevice(DiscoveredBleDevice device) async {
    final success = await bleService.pairDevice(device, dbService: dbService);
    notifyListeners();
    return success;
  }

  Future<void> unpairDevice() async {
    await bleService.unpairDevice(dbService: dbService);
    notifyListeners();
  }

  /// Automatically synchronizes offline ride sessions recorded on ESP32 MicroSD card.
  /// Triggered automatically upon BLE reconnection without requiring rider interaction.
  Future<int> autoSyncOfflineSessions() async {
    if (_isSyncing || bleService.state != BleConnectionState.connected) {
      return 0;
    }

    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStatusMessage = 'Kontrola nových jízd na motocyklu...';
    notifyListeners();

    int importedCount = 0;
    try {
      final logs = await bleService.checkOfflineLogs();
      if (logs.isNotEmpty) {
        for (int i = 0; i < logs.length; i++) {
          final logId = logs[i];
          _syncStatusMessage = 'Stahuji jízdu ${i + 1} z ${logs.length}...';
          _syncProgress = (i + 0.2) / logs.length;
          notifyListeners();

          final csvContent = await bleService.downloadOfflineLog(
            logId,
            onProgress: (bytesRead) {
              _syncStatusMessage = 'Stahuji jízdu ${i + 1} z ${logs.length} ($bytesRead B)...';
              notifyListeners();
            },
          );
          if (csvContent != null && csvContent.trim().isNotEmpty) {
            _syncStatusMessage = 'Ukládám jízdu do databáze...';
            _syncProgress = (i + 0.8) / logs.length;
            notifyListeners();

            await dbService.importRideFromCsv(
              csvContent: csvContent,
              defaultTitle: 'Synchronizovaná jízda ($logId)',
            );
            await bleService.acknowledgeOfflineLogSync(logId);
            importedCount++;
          }
        }
        _syncStatusMessage = 'Synchronizace dokončena ($importedCount jízd)';
      } else {
        _syncStatusMessage = null;
      }
    } catch (e) {
      debugPrint('[AUTO-SYNC] Error during offline sync: $e');
      _syncStatusMessage = 'Chyba synchronizace';
    } finally {
      _isSyncing = false;
      _syncProgress = 1.0;
      notifyListeners();

      // Automatically clear completion badge after 4 seconds
      _syncStatusClearTimer?.cancel();
      _syncStatusClearTimer = Timer(const Duration(seconds: 4), () {
        if (!_isSyncing) {
          _syncStatusMessage = null;
          notifyListeners();
        }
      });
    }

    return importedCount;
  }

  /// Enables or disables dedicated OBD-II Diagnostic Mode on the ESP32-S3.
  /// This is the ONLY mode in which the ESP32 transmits frames on the CAN bus.
  Future<bool> setDiagnosticMode(bool enable) async {
    if (enable) {
      if (_isRecording) {
        _diagnosticStatusMessage =
            'Diagnostiku nelze zapnout během aktivního záznamu jízdy.';
        notifyListeners();
        return false;
      }
      if (bleService.state != BleConnectionState.connected) {
        _diagnosticStatusMessage = 'Jednotka MotoLogger není připojena.';
        notifyListeners();
        return false;
      }
      if (!isSimulationMode && currentEffectiveSpeedKmh > 5.0) {
        _diagnosticStatusMessage =
            'Diagnostiku lze zapnout pouze u stojícího motocyklu (rychlost ≤ 5 km/h).';
        notifyListeners();
        return false;
      }
    }

    final active = await bleService.setDiagnosticMode(enable);
    _isDiagnosticModeActive = active;
    if (!enable) {
      _diagnosticStatusMessage = null;
    } else if (active) {
      _diagnosticStatusMessage =
          'Aktivní OBD-II diagnostika zapnuta (jednotka vysílá dotazy na CAN sběrnici).';
    }
    notifyListeners();
    return active;
  }

  /// Scans stored (Mode 03) and pending (Mode 07) OBD-II Diagnostic Trouble Codes from the ECU.
  Future<List<DiagnosticTroubleCode>> scanDiagnosticTroubleCodes() async {
    if (_isScanningDtc) return _diagnosticTroubleCodes;

    if (!isDiagnosticModeActive) {
      final enabled = await setDiagnosticMode(true);
      if (!enabled) return const [];
    }

    _isScanningDtc = true;
    _diagnosticStatusMessage =
        'Vyčítám paměť závad řídicí jednotky (OBD-II Mode 03 / Mode 07)...';
    notifyListeners();

    try {
      final codes = await bleService.readDiagnosticTroubleCodes();
      _diagnosticTroubleCodes = codes;
      _lastDtcScanTime = DateTime.now();
      _diagnosticStatusMessage = codes.isEmpty
          ? 'Paměť závad ECU je čistá (0 chyb).'
          : 'Nalezeno ${codes.length} chybových kódů v řídicí jednotce.';
      return List.unmodifiable(_diagnosticTroubleCodes);
    } finally {
      _isScanningDtc = false;
      notifyListeners();
    }
  }

  /// Clears stored and pending OBD-II Diagnostic Trouble Codes (Mode 04) from the ECU.
  Future<bool> clearDiagnosticTroubleCodes() async {
    if (_isClearingDtc) return false;

    if (!isDiagnosticModeActive) {
      final enabled = await setDiagnosticMode(true);
      if (!enabled) return false;
    }

    _isClearingDtc = true;
    _diagnosticStatusMessage = 'Mažu paměť závad ECU (OBD-II Mode 04)...';
    notifyListeners();

    try {
      final ok = await bleService.clearDiagnosticTroubleCodes();
      if (ok) {
        _diagnosticTroubleCodes = const [];
        _lastDtcScanTime = DateTime.now();
        _diagnosticStatusMessage = 'Paměť závad ECU byla úspěšně vymazána.';
      } else {
        _diagnosticStatusMessage = 'Vymazání paměti závad se nezdařilo.';
      }
      return ok;
    } finally {
      _isClearingDtc = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDiagnosticModeActive) {
      bleService.setDiagnosticMode(false);
    }
    if (gpsService.isMockMode) {
      gpsService.enableMockMode(false);
    }
    _batchFlushTimer?.cancel();
    _syncStatusClearTimer?.cancel();
    _bleSub?.cancel();
    _bleStateSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}
