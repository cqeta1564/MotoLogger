import 'telemetry_packet.dart';

class FusedSample {
  final int? id;
  final int sessionId;
  final int timestampMs;
  final DateTime recordedAt;

  // MotoLogger Hardware Data
  final double leanAngleDeg;
  final double pitchDeg;
  final double accelXG;
  final double accelYG;
  final double accelZG;
  final double gyroXDps;
  final double gyroYDps;
  final double gyroZDps;
  final int engineRpm;
  final int vehicleSpeedKmh;
  final int throttlePosPct;
  final int coolantTempC;
  final int gear;
  final double batteryVoltage;

  // Phone GPS Data
  final double latitude;
  final double longitude;
  final double altitude;
  final double gpsSpeedKmh;
  final double bearing;
  final double gpsAccuracyMeters;

  const FusedSample({
    this.id,
    required this.sessionId,
    required this.timestampMs,
    required this.recordedAt,
    required this.leanAngleDeg,
    required this.pitchDeg,
    required this.accelXG,
    required this.accelYG,
    required this.accelZG,
    required this.gyroXDps,
    required this.gyroYDps,
    required this.gyroZDps,
    required this.engineRpm,
    required this.vehicleSpeedKmh,
    required this.throttlePosPct,
    required this.coolantTempC,
    required this.gear,
    required this.batteryVoltage,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsSpeedKmh,
    required this.bearing,
    required this.gpsAccuracyMeters,
  });

  factory FusedSample.fromTelemetryAndGps({
    required int sessionId,
    required TelemetryPacket packet,
    required double latitude,
    required double longitude,
    required double altitude,
    required double gpsSpeedKmh,
    required double bearing,
    required double gpsAccuracyMeters,
  }) {
    return FusedSample(
      sessionId: sessionId,
      timestampMs: packet.timestampMs,
      recordedAt: DateTime.now(),
      leanAngleDeg: packet.leanAngleDeg,
      pitchDeg: packet.pitchDeg,
      accelXG: packet.accelXG,
      accelYG: packet.accelYG,
      accelZG: packet.accelZG,
      gyroXDps: packet.gyroXDps,
      gyroYDps: packet.gyroYDps,
      gyroZDps: packet.gyroZDps,
      engineRpm: packet.engineRpm,
      vehicleSpeedKmh: packet.vehicleSpeedKmh,
      throttlePosPct: packet.throttlePosPct,
      coolantTempC: packet.coolantTempC,
      gear: packet.gear,
      batteryVoltage: packet.batteryVoltage,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      gpsSpeedKmh: gpsSpeedKmh,
      bearing: bearing,
      gpsAccuracyMeters: gpsAccuracyMeters,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'timestamp_ms': timestampMs,
      'recorded_at': recordedAt.toIso8601String(),
      'lean_angle_deg': leanAngleDeg,
      'pitch_deg': pitchDeg,
      'accel_x_g': accelXG,
      'accel_y_g': accelYG,
      'accel_z_g': accelZG,
      'gyro_x_dps': gyroXDps,
      'gyro_y_dps': gyroYDps,
      'gyro_z_dps': gyroZDps,
      'engine_rpm': engineRpm,
      'vehicle_speed_kmh': vehicleSpeedKmh,
      'throttle_pos_pct': throttlePosPct,
      'coolant_temp_c': coolantTempC,
      'gear': gear,
      'battery_voltage': batteryVoltage,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'gps_speed_kmh': gpsSpeedKmh,
      'bearing': bearing,
      'gps_accuracy_meters': gpsAccuracyMeters,
    };
  }

  factory FusedSample.fromMap(Map<String, dynamic> map) {
    return FusedSample(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      timestampMs: map['timestamp_ms'] as int,
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      leanAngleDeg: (map['lean_angle_deg'] as num).toDouble(),
      pitchDeg: (map['pitch_deg'] as num).toDouble(),
      accelXG: (map['accel_x_g'] as num).toDouble(),
      accelYG: (map['accel_y_g'] as num).toDouble(),
      accelZG: (map['accel_z_g'] as num).toDouble(),
      gyroXDps: (map['gyro_x_dps'] as num).toDouble(),
      gyroYDps: (map['gyro_y_dps'] as num).toDouble(),
      gyroZDps: (map['gyro_z_dps'] as num).toDouble(),
      engineRpm: map['engine_rpm'] as int,
      vehicleSpeedKmh: map['vehicle_speed_kmh'] as int,
      throttlePosPct: map['throttle_pos_pct'] as int,
      coolantTempC: map['coolant_temp_c'] as int,
      gear: map['gear'] as int,
      batteryVoltage: (map['battery_voltage'] as num).toDouble(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num).toDouble(),
      gpsSpeedKmh: (map['gps_speed_kmh'] as num).toDouble(),
      bearing: (map['bearing'] as num).toDouble(),
      gpsAccuracyMeters: (map['gps_accuracy_meters'] as num).toDouble(),
    );
  }
}
