import 'package:flutter/foundation.dart';
import '../models/can_profile.dart';
import '../models/telemetry_packet.dart';
import 'database_service.dart';

/// Manages active motorcycle CAN mapping profile and signal decoding.
class CanProfileService extends ChangeNotifier {
  final DatabaseService dbService;

  BikeProfile _activeProfile = BikeProfile.standardObd();
  List<BikeProfile> _savedProfiles = [];
  bool _isLoading = true;

  BikeProfile get activeProfile => _activeProfile;
  List<BikeProfile> get savedProfiles => List.unmodifiable(_savedProfiles);
  bool get isLoading => _isLoading;
  bool get isCustomProfileActive => _activeProfile.id != 'standard_obd2';

  CanProfileService({required this.dbService}) {
    loadProfiles();
  }

  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _savedProfiles = await dbService.getAllBikeProfiles();
      final activeId = await dbService.getSetting('active_bike_profile_id');

      if (activeId != null && activeId.isNotEmpty) {
        final found = _savedProfiles.where((p) => p.id == activeId).firstOrNull;
        if (found != null) {
          _activeProfile = found;
        } else {
          _activeProfile = BikeProfile.standardObd();
        }
      } else {
        _activeProfile = BikeProfile.standardObd();
      }
    } catch (e) {
      debugPrint('[CAN PROFILE] Error loading profiles: $e');
      _activeProfile = BikeProfile.standardObd();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setActiveProfile(BikeProfile profile) async {
    _activeProfile = profile;
    await dbService.saveSetting('active_bike_profile_id', profile.id);
    notifyListeners();
  }

  Future<void> setStandardObdActive() async {
    _activeProfile = BikeProfile.standardObd();
    await dbService.saveSetting('active_bike_profile_id', 'standard_obd2');
    notifyListeners();
  }

  Future<void> saveAndActivateProfile(BikeProfile profile) async {
    await dbService.saveBikeProfile(profile);
    _activeProfile = profile;
    await dbService.saveSetting('active_bike_profile_id', profile.id);
    await loadProfiles();
  }

  Future<void> deleteProfile(String id) async {
    await dbService.deleteBikeProfile(id);
    if (_activeProfile.id == id) {
      await setStandardObdActive();
    } else {
      await loadProfiles();
    }
  }

  /// Decodes incoming raw CAN frame and applies mapped parameters to TelemetryPacket.
  TelemetryPacket decodeFrame(int canId, List<int> payload, TelemetryPacket currentPacket) {
    if (!isCustomProfileActive || payload.isEmpty) {
      return currentPacket;
    }

    TelemetryPacket updated = currentPacket;

    // Check RPM
    final rpm = _activeProfile.rpmSignal;
    if (rpm != null && rpm.numericCanId == canId) {
      final val = rpm.decodeValue(payload);
      if (val != null) {
        updated = updated.copyWith(engineRpm: val.round().clamp(0, 25000));
      }
    }

    // Check Speed
    final speed = _activeProfile.speedSignal;
    if (speed != null && speed.numericCanId == canId) {
      final val = speed.decodeValue(payload);
      if (val != null) {
        updated = updated.copyWith(vehicleSpeedKmh: val.round().clamp(0, 399));
      }
    }

    // Check Throttle
    final tps = _activeProfile.throttleSignal;
    if (tps != null && tps.numericCanId == canId) {
      final val = tps.decodeValue(payload);
      if (val != null) {
        updated = updated.copyWith(throttlePosPct: val.round().clamp(0, 100));
      }
    }

    // Check Gear
    final gear = _activeProfile.gearSignal;
    if (gear != null && gear.numericCanId == canId) {
      final val = gear.decodeValue(payload);
      if (val != null) {
        updated = updated.copyWith(gear: val.round().clamp(-1, 8));
      }
    }

    // Check Coolant Temp
    final temp = _activeProfile.coolantSignal;
    if (temp != null && temp.numericCanId == canId) {
      final val = temp.decodeValue(payload);
      if (val != null) {
        updated = updated.copyWith(coolantTempC: val.round().clamp(-40, 160));
      }
    }

    return updated;
  }
}
