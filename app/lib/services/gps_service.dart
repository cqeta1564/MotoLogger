import 'dart:async';
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
        _lastPosition = position;
        _positionController.add(position);
      });

      return true;
    } catch (e) {
      debugPrint('[GPS] Error initializing GPS: $e');
      return false;
    }
  }

  void stop() {
    _positionSubscription?.cancel();
  }

  void dispose() {
    stop();
    _positionController.close();
  }
}
