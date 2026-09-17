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
  List<double> get frictionEnvelopeRadii =>
      List.unmodifiable(_frictionEnvelope);

  // Automatic offline sync state
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String? _syncStatusMessage;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String? get syncStatusMessage => _syncStatusMessage;

  bool get isSimulationMode => bleService.isMockMode || gpsService.isMockMode;

  void setSimulationMode(bool enable) {
    if (_isRecording || _starting != null) return;
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

      final currentG = sqrt(adjustedPacket.accelXG * adjustedPacket.accelXG +
          adjustedPacket.accelYG * adjustedPacket.accelYG);
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
          gpsSpeedKmh:
              _latestPosition != null ? (_latestPosition!.speed * 3.6) : 0.0,
          bearing: _latestPosition?.heading ?? 0.0,
          gpsAccuracyMeters: _latestPosition?.accuracy ?? 0.0,
        );

        _sampleBuffer.add(sample);

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

          final csvContent = await bleService.downloadOfflineLog(logId);
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

  @override
  void dispose() {
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
