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
  static const int cmdSetCanSignal = 0x03; // Set CAN signal mapping (17 bytes: signal, ID, start, len, endian, mult, offset)
  static const int cmdSetCanProfileMode = 0x04; // 1 = Custom CAN profile active, 0 = Standard OBD

  // CAN Signal Indices matching ESP32 firmware CanSignalType enum
  static const int canSignalRpm = 0;
  static const int canSignalSpeed = 1;
  static const int canSignalThrottle = 2;
  static const int canSignalGear = 3;
  static const int canSignalCoolant = 4;
}
