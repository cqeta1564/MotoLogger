class BleConstants {
  static const String deviceName = 'MotoLogger-ESP32';
  
  // Custom 128-bit UUIDs matching MotoLogger ESP32-S3 firmware
  static const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
  static const String telemetryCharUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
  static const String commandCharUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';

  // Packet format constants
  static const int expectedPacketLength = 28;

  // Mobile -> ESP32 Commands
  static const int cmdTareZero = 0x01; // Zero-tare IMU lean and pitch calibration
  static const int cmdTareWithOffset = 0x02; // Set mounting roll offset in tenths of a degree (int16_t)
}
