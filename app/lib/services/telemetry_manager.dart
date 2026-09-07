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

class TelemetryManager extends ChangeNotifier {
  final BleService bleService;
  final GpsService gpsService;
  final DatabaseService dbService;

  TelemetryPacket _latestPacket = TelemetryPacket.initial();
  Position? _latestPosition;

  bool _isRecording = false;
  int? _currentSessionId;
  String _sessionTitle = 'Track Ride';
  DateTime? _sessionStartTime;

  double _maxLeanLeft = 0.0;
  double _maxLeanRight = 0.0;
  double _topSpeed = 0.0;
  double _maxG = 0.0;
  double _totalDistanceKm = 0.0;
  int _sampleCount = 0;

  final List<FusedSample> _sampleBuffer = [];
  Timer? _batchFlushTimer;
  StreamSubscription? _bleSub;
  StreamSubscription? _gpsSub;

  TelemetryPacket get latestPacket => _latestPacket;
  Position? get latestPosition => _latestPosition;
  bool get isRecording => _isRecording;
  double get maxLeanLeft => _maxLeanLeft;
  double get maxLeanRight => _maxLeanRight;
  double get topSpeed => _topSpeed;
  double get maxG => _maxG;
  double get totalDistanceKm => _totalDistanceKm;
  int get sampleCount => _sampleCount;

  TelemetryManager({
    required this.bleService,
    required this.gpsService,
    required this.dbService,
  }) {
    _initListeners();
  }

  void _initListeners() {
    _bleSub = bleService.telemetryStream.listen((packet) {
      _latestPacket = packet;

      // Update real-time peak dynamics
      if (packet.leanAngleDeg < _maxLeanLeft) {
        _maxLeanLeft = packet.leanAngleDeg;
      }
      if (packet.leanAngleDeg > _maxLeanRight) {
        _maxLeanRight = packet.leanAngleDeg;
      }
      if (packet.vehicleSpeedKmh > _topSpeed) {
        _topSpeed = packet.vehicleSpeedKmh.toDouble();
      }

      final currentG = sqrt(packet.accelXG * packet.accelXG + packet.accelYG * packet.accelYG);
      if (currentG > _maxG) {
        _maxG = currentG;
      }

      // If session recording is active, fuse with GPS and buffer
      if (_isRecording && _currentSessionId != null) {
        _sampleCount++;
        final sample = FusedSample.fromTelemetryAndGps(
          sessionId: _currentSessionId!,
          packet: packet,
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
      if (_latestPosition != null && _isRecording) {
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

    _currentSessionId = await dbService.startSession(_sessionTitle);
    _isRecording = true;
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
    _currentSessionId = null;
    notifyListeners();
  }

  Future<void> _flushBuffer() async {
    if (_sampleBuffer.isEmpty) return;
    final toWrite = List<FusedSample>.from(_sampleBuffer);
    _sampleBuffer.clear();
    await dbService.insertSampleBatch(toWrite);
  }

  Future<void> tareZero() async {
    await bleService.sendTareZero();
  }

  @override
  void dispose() {
    _batchFlushTimer?.cancel();
    _bleSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}
