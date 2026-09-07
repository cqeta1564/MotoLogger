import 'dart:typed_data';

class TelemetryPacket {
  final int timestampMs;
  final double leanAngleDeg;    // Roll (+ right, - left)
  final double pitchDeg;        // Pitch (+ accel/wheelie, - braking)
  final double accelXG;         // Longitudinal acceleration (G)
  final double accelYG;         // Lateral acceleration (G)
  final double accelZG;         // Vertical acceleration (G)
  final double gyroXDps;        // Roll rate (deg/s)
  final double gyroYDps;        // Pitch rate (deg/s)
  final double gyroZDps;        // Yaw rate (deg/s)
  final int engineRpm;          // RPM (0 - 20000)
  final int vehicleSpeedKmh;    // Speed in km/h
  final int throttlePosPct;     // Throttle (0 - 100 %)
  final int coolantTempC;       // Engine coolant temp (deg C)
  final int gear;               // -1 = unknown, 0 = N, 1..6
  final double batteryVoltage;  // Battery voltage (V)
  final int statusFlags;        // Status bitmask

  const TelemetryPacket({
    required this.timestampMs,
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
    required this.statusFlags,
  });

  bool get isSdLoggingActive => (statusFlags & (1 << 0)) != 0;
  bool get isEngineRunning => (statusFlags & (1 << 1)) != 0;
  bool get isShutdownCountdown => (statusFlags & (1 << 2)) != 0;
  bool get isImuHealthy => (statusFlags & (1 << 3)) != 0;

  // Zero-copy binary parser from incoming BLE notification byte buffer
  factory TelemetryPacket.fromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 28) {
      throw FormatException('BLE packet too short: ${bytes.lengthInBytes} bytes (expected >= 28)');
    }

    final ByteData data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);

    final int ts = data.getUint32(0, Endian.little);
    final double roll = data.getInt16(4, Endian.little) / 10.0;
    final double pitch = data.getInt16(6, Endian.little) / 10.0;
    final double ax = data.getInt16(8, Endian.little) / 1000.0;
    final double ay = data.getInt16(10, Endian.little) / 1000.0;
    final double az = data.getInt16(12, Endian.little) / 1000.0;
    final double gx = data.getInt16(14, Endian.little) / 10.0;
    final double gy = data.getInt16(16, Endian.little) / 10.0;
    final double gz = data.getInt16(18, Endian.little) / 10.0;
    final int rpm = data.getUint16(20, Endian.little);
    final int spd = data.getUint8(22);
    final int tps = data.getUint8(23);
    final int temp = data.getInt8(24);
    final int gr = data.getInt8(25);
    final double vbat = data.getUint16(26, Endian.little) / 1000.0;
    final int flags = (bytes.lengthInBytes >= 29) ? data.getUint8(28) : 0;

    return TelemetryPacket(
      timestampMs: ts,
      leanAngleDeg: roll,
      pitchDeg: pitch,
      accelXG: ax,
      accelYG: ay,
      accelZG: az,
      gyroXDps: gx,
      gyroYDps: gy,
      gyroZDps: gz,
      engineRpm: rpm,
      vehicleSpeedKmh: spd,
      throttlePosPct: tps,
      coolantTempC: temp,
      gear: gr,
      batteryVoltage: vbat,
      statusFlags: flags,
    );
  }

  factory TelemetryPacket.initial() {
    return const TelemetryPacket(
      timestampMs: 0,
      leanAngleDeg: 0.0,
      pitchDeg: 0.0,
      accelXG: 0.0,
      accelYG: 0.0,
      accelZG: 1.0,
      gyroXDps: 0.0,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      engineRpm: 0,
      vehicleSpeedKmh: 0,
      throttlePosPct: 0,
      coolantTempC: 20,
      gear: 0,
      batteryVoltage: 12.6,
      statusFlags: 0,
    );
  }
}
