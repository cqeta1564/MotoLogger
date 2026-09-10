import 'package:flutter_test/flutter_test.dart';
import 'package:motologger/models/can_profile.dart';
import 'package:motologger/services/can_learning_service.dart';
import 'package:motologger/services/ble_service.dart';
import 'package:motologger/services/gps_service.dart';

void main() {
  group('CanSignalMapping Tests', () {
    test('Decodes 1-byte signal with multiplier and offset', () {
      const mapping = CanSignalMapping(
        key: 'coolant_temp',
        canId: '0x280',
        startByte: 0,
        lengthBytes: 1,
        multiplier: 1.0,
        offset: -40.0,
        unit: '°C',
      );

      // 128 - 40 = 88 °C
      final payload = [128, 0, 0, 0, 0, 0, 0, 0];
      final val = mapping.decodeValue(payload);

      expect(val, isNotNull);
      expect(val, equals(88.0));
      expect(mapping.numericCanId, equals(0x280));
    });

    test('Decodes 2-byte Big Endian RPM signal', () {
      const mapping = CanSignalMapping(
        key: 'engine_rpm',
        canId: '0x1F0',
        startByte: 0,
        lengthBytes: 2,
        isBigEndian: true,
        multiplier: 1.0,
        offset: 0.0,
        unit: 'RPM',
      );

      // (0x17 << 8) | 0x70 = 6000
      final payload = [0x17, 0x70, 0, 0, 0, 0, 0, 0];
      final val = mapping.decodeValue(payload);

      expect(val, isNotNull);
      expect(val, equals(6000.0));
    });

    test('Decodes 2-byte Little Endian Speed signal with multiplier', () {
      const mapping = CanSignalMapping(
        key: 'vehicle_speed',
        canId: '0x1F0',
        startByte: 2,
        lengthBytes: 2,
        isBigEndian: false,
        multiplier: 0.05,
        offset: 0.0,
        unit: 'km/h',
      );

      // 1000 * 0.05 = 50 km/h -> 1000 = 0x03E8 -> Little Endian = [0xE8, 0x03]
      final payload = [0, 0, 0xE8, 0x03, 0, 0, 0, 0];
      final val = mapping.decodeValue(payload);

      expect(val, isNotNull);
      expect(val, equals(50.0));
    });

    test('Returns null safely when payload is too short', () {
      const mapping = CanSignalMapping(
        key: 'gear',
        canId: '0x208',
        startByte: 6,
        lengthBytes: 2,
      );

      final shortPayload = [1, 2, 3];
      expect(mapping.decodeValue(shortPayload), isNull);
    });
  });

  group('BikeProfile AI JSON Parsing Tests', () {
    test('Parses clean raw JSON response', () {
      const jsonStr = '''
      {
        "bike_name": "Yamaha MT-09 2021",
        "can_bus_baudrate": 500000,
        "signals": {
          "engine_rpm": {
            "can_id": "0x1F0",
            "start_byte": 0,
            "length_bytes": 2,
            "endianness": "big",
            "multiplier": 1.0,
            "offset": 0.0,
            "unit": "RPM"
          },
          "vehicle_speed": {
            "can_id": "0x1F0",
            "start_byte": 2,
            "length_bytes": 2,
            "endianness": "big",
            "multiplier": 0.05,
            "offset": 0.0,
            "unit": "km/h"
          }
        }
      }
      ''';

      final profile = BikeProfile.fromAiJson(jsonStr);

      expect(profile.name, equals('Yamaha MT-09 2021'));
      expect(profile.canBaudrate, equals(500000));
      expect(profile.rpmSignal, isNotNull);
      expect(profile.rpmSignal!.canId, equals('0x1F0'));
      expect(profile.speedSignal, isNotNull);
      expect(profile.speedSignal!.multiplier, equals(0.05));
    });

    test('Parses markdown code block wrapped JSON', () {
      const markdown = '''
Here is the reverse-engineered CAN mapping for your bike:

```json
{
  "bike_name": "KTM 890 Duke R",
  "can_bus_baudrate": 500000,
  "signals": {
    "throttle_pos": {
      "can_id": "0x208",
      "start_byte": 1,
      "length_bytes": 1,
      "endianness": "little",
      "multiplier": 0.392,
      "offset": 0.0,
      "unit": "%"
    }
  }
}
```

Good luck with your telemetry logging!
''';

      final profile = BikeProfile.fromAiJson(markdown);

      expect(profile.name, equals('KTM 890 Duke R'));
      expect(profile.throttleSignal, isNotNull);
      expect(profile.throttleSignal!.canId, equals('0x208'));
    });

    test('Throws FormatException for invalid JSON', () {
      expect(() => BikeProfile.fromAiJson('No JSON here at all!'), throwsFormatException);
    });

    test('Serialization toMap and fromMap works symmetrically', () {
      final original = BikeProfile.standardObd();
      final map = original.toMap();
      final reconstructed = BikeProfile.fromMap(map);

      expect(reconstructed.name, equals(original.name));
      expect(reconstructed.signals.length, equals(original.signals.length));
      expect(reconstructed.rpmSignal?.canId, equals(original.rpmSignal?.canId));
    });
  });

  group('CanLearningService Tests', () {
    test('Generates AI prompt with required signals and instructions', () {
      final ble = BleService();
      final gps = GpsService();
      final service = CanLearningService(bleService: ble, gpsService: gps);

      final prompt = service.generateAiPrompt();

      expect(prompt, contains('engine_rpm'));
      expect(prompt, contains('vehicle_speed'));
      expect(prompt, contains('throttle_pos'));
      expect(prompt, contains('coolant_temp'));
      expect(prompt, contains('can_bus_baudrate'));
      expect(prompt, contains('Output ONLY a valid JSON object'));
    });

    test('Imports raw SD card CSV lines and generates dataset summary', () async {
      final ble = BleService();
      final gps = GpsService();
      final service = CanLearningService(bleService: ble, gpsService: gps);

      const fakeSdCsv = '''
timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,v_bat,engine_rpm,vehicle_speed_kmh,throttle_pos_pct,coolant_temp_c,gear
#CAN,1000000,0x1F0,8,17,70,03,E8,00,00,12,34
#CAN,1020000,0x1F0,8,18,00,04,B0,00,00,12,34
#CAN,1040000,0x208,8,01,FF,00,00,02,55,AA,00
''';

      final imported = await service.importFromSdCsv(fakeSdCsv);

      expect(imported, equals(3));
      expect(service.capturedFrameCount, equals(3));
      expect(service.uniqueCanIdCount, equals(2));

      final dataset = service.generateDatasetSummary();
      expect(dataset['total_can_frames_captured'], equals(3));
      expect(dataset['unique_can_ids_detected'], equals(2));
    });
  });

  group('BleService CAN Profile Upload Tests', () {
    test('Uploads bike profile via mock BleService', () async {
      final ble = BleService();
      ble.enableMockMode(true);

      final profile = BikeProfile.standardObd();
      final success = await ble.uploadBikeProfile(profile);

      expect(success, isTrue);
    });

    test('Uploads custom bike profile signals via mock BleService', () async {
      final ble = BleService();
      ble.enableMockMode(true);

      const jsonStr = '''
      {
        "bike_name": "Ducati Monster",
        "signals": {
          "engine_rpm": {
            "can_id": "0x1F0",
            "start_byte": 0,
            "length_bytes": 2,
            "endianness": "big",
            "multiplier": 1.0,
            "offset": 0.0,
            "unit": "RPM"
          }
        }
      }
      ''';
      final profile = BikeProfile.fromAiJson(jsonStr);
      final success = await ble.uploadBikeProfile(profile);

      expect(success, isTrue);
    });
  });
}
