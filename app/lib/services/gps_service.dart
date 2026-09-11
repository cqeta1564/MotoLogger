import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GpsService {
  final _positionController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionController.stream;

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  bool _isServiceEnabled = false;
  bool get isServiceEnabled => _isServiceEnabled;

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;
  Timer? _mockTimer;
  double _mockTrackDistanceMeters = 0.0;

  Future<bool> initialize() async {
    try {
      _isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isServiceEnabled) {
        debugPrint('[GPS] Location services are disabled.');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[GPS] Location permissions are denied.');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Location permissions are permanently denied.');
        return false;
      }

      // Configure high-rate navigation GPS listener (optimized for motorcycle dynamics)
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1, // trigger every 1 meter
      );

      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen((Position position) {
        if (!_isMockMode) {
          _lastPosition = position;
          _positionController.add(position);
        }
      });

      return true;
    } catch (e) {
      debugPrint('[GPS] Error initializing GPS: $e');
      return false;
    }
  }

  // ================= DEMO / SIMULATION GPS GENERATOR =================
  // Simulates a realistic motorcycle lap on Automotodrom Brno (Masarykův okruh).
  void enableMockMode(bool enable) {
    _isMockMode = enable;
    _mockTimer?.cancel();
    _mockTimer = null;

    if (enable) {
      _initTrackDistances();
      final initialPos = _computeMockPositionAt(_mockTrackDistanceMeters);
      _lastPosition = initialPos;
      _positionController.add(initialPos);

      // 10 Hz high-precision GNSS stream (every 100ms)
      _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final currentPos = _computeMockPositionAt(_mockTrackDistanceMeters);
        final deltaMeters = currentPos.speed * 0.1; // 0.1 sec step
        final total = _totalTrackLengthMeters > 0 ? _totalTrackLengthMeters : 5400.0;
        _mockTrackDistanceMeters = (_mockTrackDistanceMeters + deltaMeters) % total;

        _lastPosition = currentPos;
        _positionController.add(currentPos);
      });
    }
  }

  Position _computeMockPositionAt(double currentDist) {
    _initTrackDistances();
    final total = _totalTrackLengthMeters > 0 ? _totalTrackLengthMeters : 5400.0;
    final normDist = currentDist % total;

    int segIdx = 0;
    for (int i = 0; i < _segmentCumulativeDistances!.length - 1; i++) {
      if (normDist >= _segmentCumulativeDistances![i] &&
          normDist <= _segmentCumulativeDistances![i + 1]) {
        segIdx = i;
        break;
      }
    }

    final p1 = _brnoCircuit[segIdx];
    final p2 = _brnoCircuit[segIdx + 1];
    final segStart = _segmentCumulativeDistances![segIdx];
    final segEnd = _segmentCumulativeDistances![segIdx + 1];
    final segLen = (segEnd - segStart).clamp(1.0, 10000.0);
    final t = ((normDist - segStart) / segLen).clamp(0.0, 1.0);

    final lat = p1.lat + t * (p2.lat - p1.lat);
    final lon = p1.lon + t * (p2.lon - p1.lon);
    final alt = p1.alt + t * (p2.alt - p1.alt);
    final speedKmh = p1.speedKmh + t * (p2.speedKmh - p1.speedKmh);
    final speedMs = speedKmh / 3.6;
    final bearing = _calculateBearing(p1.lat, p1.lon, p2.lat, p2.lon);

    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 1.8,
      altitude: alt,
      altitudeAccuracy: 1.2,
      heading: bearing,
      headingAccuracy: 1.5,
      speed: speedMs,
      speedAccuracy: 0.3,
      isMocked: true,
    );
  }

  static double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * pi / 180.0;
    final phi2 = lat2 * pi / 180.0;
    final deltaLambda = (lon2 - lon1) * pi / 180.0;

    final y = sin(deltaLambda) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda);
    final theta = atan2(y, x);
    return (theta * 180.0 / pi + 360.0) % 360.0;
  }

  static double _approxDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static List<double>? _segmentCumulativeDistances;
  static double _totalTrackLengthMeters = 0.0;

  static void _initTrackDistances() {
    if (_segmentCumulativeDistances != null) return;
    _segmentCumulativeDistances = [0.0];
    double running = 0.0;
    for (int i = 0; i < _brnoCircuit.length - 1; i++) {
      final p1 = _brnoCircuit[i];
      final p2 = _brnoCircuit[i + 1];
      final d = _approxDistanceMeters(p1.lat, p1.lon, p2.lat, p2.lon);
      running += d;
      _segmentCumulativeDistances!.add(running);
    }
    _totalTrackLengthMeters = running;
  }

  static const List<_TrackWaypoint> _brnoCircuit = [
    // 1. Cílová rovinka (Start/Finish straight)
    _TrackWaypoint(49.20410, 16.44810, 385.0, 165.0),
    // 2. Konec cílové rovinky před T1
    _TrackWaypoint(49.20620, 16.44760, 388.0, 130.0),
    // 3. T1 (První pravá zatáčka)
    _TrackWaypoint(49.20740, 16.44680, 392.0, 85.0),
    // 4. Mezi T1 a T2 (Stadion)
    _TrackWaypoint(49.20830, 16.44490, 396.0, 110.0),
    // 5. T2 (Levá do stadionu)
    _TrackWaypoint(49.20860, 16.44310, 400.0, 80.0),
    // 6. T3 (Pravá výjezd ze stadionu)
    _TrackWaypoint(49.20770, 16.44080, 405.0, 88.0),
    // 7. T4 (Levá táhlá do kopce)
    _TrackWaypoint(49.20580, 16.43880, 415.0, 105.0),
    // 8. Stoupání k lesu (Uphill fast section)
    _TrackWaypoint(49.20320, 16.43700, 428.0, 140.0),
    // 9. T5 (Vrchol stoupání)
    _TrackWaypoint(49.20050, 16.43670, 436.0, 115.0),
    // 10. T6 / T7 (Klimex šikana)
    _TrackWaypoint(49.19820, 16.43810, 442.0, 82.0),
    _TrackWaypoint(49.19690, 16.44050, 444.0, 85.0),
    // 11. T8 / T9 (Schwantzova zatáčka)
    _TrackWaypoint(49.19660, 16.44360, 439.0, 92.0),
    _TrackWaypoint(49.19770, 16.44630, 427.0, 120.0),
    // 12. Lesní klesání (Fast downhill sweepers)
    _TrackWaypoint(49.19960, 16.44890, 412.0, 145.0),
    // 13. T10 / T11 (Vjezd do Omegy)
    _TrackWaypoint(49.20140, 16.45180, 398.0, 95.0),
    // 14. T12 (Kolem tribuny C - Omega)
    _TrackWaypoint(49.20290, 16.45260, 393.0, 88.0),
    // 15. T13 / T14 (Poslední šikana před cílem)
    _TrackWaypoint(49.20360, 16.45040, 388.0, 82.0),
    // 16. Zpět na start/cíl
    _TrackWaypoint(49.20410, 16.44810, 385.0, 165.0),
  ];

  void stop() {
    _mockTimer?.cancel();
    _mockTimer = null;
    _positionSubscription?.cancel();
  }

  void dispose() {
    stop();
    _positionController.close();
  }
}

class _TrackWaypoint {
  final double lat;
  final double lon;
  final double alt;
  final double speedKmh;

  const _TrackWaypoint(this.lat, this.lon, this.alt, this.speedKmh);
}
