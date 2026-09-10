import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Mapping configuration for a single CAN bus signal (e.g. RPM, Speed, Gear).
class CanSignalMapping {
  final String key;
  final String canId; // Hex representation, e.g. "0x1F0"
  final int startByte; // 0..7
  final int lengthBytes; // 1 or 2
  final bool isBigEndian; // True = MSB first, False = LSB first
  final double multiplier; // Scale factor
  final double offset; // Additive offset
  final String unit; // e.g. "RPM", "km/h", "%", "°C"

  const CanSignalMapping({
    required this.key,
    required this.canId,
    required this.startByte,
    this.lengthBytes = 1,
    this.isBigEndian = true,
    this.multiplier = 1.0,
    this.offset = 0.0,
    this.unit = '',
  });

  /// Parse normalized CAN ID integer from string (handles "0x1F0", "1F0", etc.)
  int get numericCanId {
    final cleaned = canId.trim().toLowerCase().replaceAll('0x', '');
    return int.tryParse(cleaned, radix: 16) ?? 0;
  }

  /// Extracts and calculates the real physical value from raw 8-byte payload.
  double? decodeValue(List<int> payload) {
    if (payload.length < startByte + lengthBytes) {
      return null;
    }

    int rawInt = 0;
    if (lengthBytes == 1) {
      rawInt = payload[startByte];
    } else if (lengthBytes == 2) {
      if (isBigEndian) {
        rawInt = (payload[startByte] << 8) | payload[startByte + 1];
      } else {
        rawInt = payload[startByte] | (payload[startByte + 1] << 8);
      }
    } else if (lengthBytes == 4) {
      if (isBigEndian) {
        rawInt = (payload[startByte] << 24) |
            (payload[startByte + 1] << 16) |
            (payload[startByte + 2] << 8) |
            payload[startByte + 3];
      } else {
        rawInt = payload[startByte] |
            (payload[startByte + 1] << 8) |
            (payload[startByte + 2] << 16) |
            (payload[startByte + 3] << 24);
      }
    }

    return (rawInt * multiplier) + offset;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'can_id': canId,
        'start_byte': startByte,
        'length_bytes': lengthBytes,
        'endianness': isBigEndian ? 'big' : 'little',
        'multiplier': multiplier,
        'offset': offset,
        'unit': unit,
      };

  factory CanSignalMapping.fromJson(String key, Map<String, dynamic> json) {
    final endianness = json['endianness']?.toString().toLowerCase() ?? 'big';
    return CanSignalMapping(
      key: key,
      canId: json['can_id']?.toString() ?? '0x000',
      startByte: (json['start_byte'] as num?)?.toInt() ?? 0,
      lengthBytes: (json['length_bytes'] as num?)?.toInt() ?? 1,
      isBigEndian: endianness != 'little',
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit']?.toString() ?? '',
    );
  }
}

/// Motorcycle CAN Bus interpretation profile.
class BikeProfile {
  final String id;
  final String name;
  final DateTime createdAt;
  final int canBaudrate;
  final Map<String, CanSignalMapping> signals;
  final String rawAiJson;

  const BikeProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    this.canBaudrate = 500000,
    required this.signals,
    this.rawAiJson = '',
  });

  CanSignalMapping? get rpmSignal => signals['engine_rpm'];
  CanSignalMapping? get speedSignal => signals['vehicle_speed'];
  CanSignalMapping? get throttleSignal => signals['throttle_pos'];
  CanSignalMapping? get gearSignal => signals['gear'];
  CanSignalMapping? get coolantSignal => signals['coolant_temp'];

  /// Standard factory fallback for OBD-II standard mode
  factory BikeProfile.standardObd() {
    return BikeProfile(
      id: 'standard_obd2',
      name: 'Standardní OBD-II (Výchozí)',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      canBaudrate: 500000,
      signals: const {
        'engine_rpm': CanSignalMapping(
          key: 'engine_rpm',
          canId: '0x7E8',
          startByte: 3,
          lengthBytes: 2,
          isBigEndian: true,
          multiplier: 0.25,
          offset: 0.0,
          unit: 'RPM',
        ),
        'vehicle_speed': CanSignalMapping(
          key: 'vehicle_speed',
          canId: '0x7E8',
          startByte: 3,
          lengthBytes: 1,
          isBigEndian: true,
          multiplier: 1.0,
          offset: 0.0,
          unit: 'km/h',
        ),
        'throttle_pos': CanSignalMapping(
          key: 'throttle_pos',
          canId: '0x7E8',
          startByte: 3,
          lengthBytes: 1,
          isBigEndian: true,
          multiplier: 0.392157, // 100 / 255
          offset: 0.0,
          unit: '%',
        ),
        'coolant_temp': CanSignalMapping(
          key: 'coolant_temp',
          canId: '0x7E8',
          startByte: 3,
          lengthBytes: 1,
          isBigEndian: true,
          multiplier: 1.0,
          offset: -40.0,
          unit: '°C',
        ),
      },
      rawAiJson: '',
    );
  }

  /// Robust parser for AI responses: handles pure JSON, markdown blocks, and surrounding chat text.
  factory BikeProfile.fromAiJson(String input, {String? customName}) {
    String cleaned = input.trim();

    // 1. Strip markdown code block markers
    if (cleaned.contains('```json')) {
      final startIndex = cleaned.indexOf('```json') + 7;
      final endIndex = cleaned.lastIndexOf('```');
      if (endIndex > startIndex) {
        cleaned = cleaned.substring(startIndex, endIndex).trim();
      }
    } else if (cleaned.contains('```')) {
      final startIndex = cleaned.indexOf('```') + 3;
      final endIndex = cleaned.lastIndexOf('```');
      if (endIndex > startIndex) {
        cleaned = cleaned.substring(startIndex, endIndex).trim();
      }
    }

    // 2. Extract substring between first '{' and last '}'
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
      throw const FormatException('V odpovědi nebyl nalezen platný JSON objekt.');
    }

    cleaned = cleaned.substring(firstBrace, lastBrace + 1);

    final dynamic parsed = jsonDecode(cleaned);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('JSON neobsahuje kořenový objekt.');
    }

    final String bikeName = customName ??
        parsed['bike_name']?.toString() ??
        parsed['name']?.toString() ??
        'Neznámý motocykl';

    final int baudrate = (parsed['can_bus_baudrate'] as num?)?.toInt() ?? 500000;

    final Map<String, CanSignalMapping> signalMap = {};
    final signalsData = parsed['signals'];

    if (signalsData is Map<String, dynamic>) {
      signalsData.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          try {
            signalMap[k] = CanSignalMapping.fromJson(k, v);
          } catch (e) {
            debugPrint('[CAN PROFILE] Error parsing signal $k: $e');
          }
        }
      });
    }

    if (signalMap.isEmpty) {
      throw const FormatException('V profilu nebyly nalezeny žádné platné definice signálů.');
    }

    return BikeProfile(
      id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
      name: bikeName,
      createdAt: DateTime.now(),
      canBaudrate: baudrate,
      signals: signalMap,
      rawAiJson: input,
    );
  }

  Map<String, dynamic> toMap() {
    final signalJsonMap = <String, dynamic>{};
    signals.forEach((k, v) => signalJsonMap[k] = v.toJson());

    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'can_baudrate': canBaudrate,
      'signals_json': jsonEncode(signalJsonMap),
      'raw_ai_json': rawAiJson,
    };
  }

  factory BikeProfile.fromMap(Map<String, dynamic> map) {
    final signalsRaw = jsonDecode(map['signals_json'] as String) as Map<String, dynamic>;
    final signalsMap = <String, CanSignalMapping>{};
    signalsRaw.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        signalsMap[k] = CanSignalMapping.fromJson(k, v);
      }
    });

    return BikeProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
      canBaudrate: (map['can_baudrate'] as num?)?.toInt() ?? 500000,
      signals: signalsMap,
      rawAiJson: map['raw_ai_json'] as String? ?? '',
    );
  }
}
