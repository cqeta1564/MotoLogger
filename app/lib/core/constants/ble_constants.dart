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
  static const int cmdSyncCheck = 0x20; // Query ESP32 for un-synced offline session logs on SD card
  static const int cmdSyncRequestFile = 0x21; // Request chunked transfer of specific offline session
  static const int cmdSyncAck = 0x22; // Acknowledge successful session sync
  static const int cmdSyncCheckLegacy = 0x05;
  static const int cmdSyncRequestFileLegacy = 0x06;
  static const int cmdSyncAckLegacy = 0x07;

  // Dedicated OBD-II Diagnostic Mode Commands (Only mode with active CAN TX)
  static const int cmdDiagSetMode = 0x30; // Payload: [1 = Enable ACTIVE_OBD TX, 0 = Disable / Listen-Only]
  static const int cmdDiagReadDtc = 0x31; // Request OBD-II Mode 03 (Stored) & Mode 07 (Pending) DTC scan
  static const int cmdDiagClearDtc = 0x32; // Request OBD-II Mode 04 (Clear DTCs / Reset MIL)

  // CAN Sniffer Mode (Passive Listen-Only Stream)
  static const int cmdCanSnifferMode = 0x40; // Payload: [1 = Enable sniffer stream, 0 = Disable]

  // OTA Firmware Update Mode (SoftAP at 192.168.4.1)
  static const int cmdOtaSetMode = 0x50; // Payload: [1 = Enable Wi-Fi AP, 0 = Disable]

  // ESP32 -> Mobile Command Responses
  static const int respSyncCheck = 0xA0; // 0x20 | 0x80
  static const int respSyncCheckLegacy = 0x85; // 0x05 | 0x80
  static const int respSyncChunk = 0xA1; // 0x21 | 0x80
  static const int respSyncChunkLegacy = 0x86; // 0x06 | 0x80
  static const int respSyncAck = 0xA2; // 0x22 | 0x80
  static const int respSyncAckLegacy = 0x87; // 0x07 | 0x80
  static const int respDiagMode = 0xB0; // 0x30 | 0x80 -> [0xB0, active(0/1)]
  static const int respDiagDtcList = 0xB1; // 0x31 | 0x80 -> [0xB1, count, "P0122:S;C0035:P"...]
  static const int respDiagClearAck = 0xB2; // 0x32 | 0x80 -> [0xB2, status(0/1)]
  static const int respCanRawFrame = 0xC0; // 0x40 | 0x80 -> [0xC0, can_id(4 LE), dlc(1), data(8)]
  static const int respOtaStatus = 0xD0; // 0x50 | 0x80 -> [0xD0, state(1), ip(4)]

  // CAN Signal Indices matching ESP32 firmware CanSignalType enum
  static const int canSignalRpm = 0;
  static const int canSignalSpeed = 1;
  static const int canSignalThrottle = 2;
  static const int canSignalGear = 3;
  static const int canSignalCoolant = 4;
}
