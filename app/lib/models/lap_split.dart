class LapSplit {
  final int lapNumber;
  final Duration lapTime;
  final int lapTimeMs;
  final int startTimestampMs;
  final int endTimestampMs;
  final int startSampleIndex;
  final int endSampleIndex;
  final double topSpeedKmh;
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;
  final double maxGForce;
  final Duration deltaToBest;
  final int deltaMs;
  final bool isBestLap;

  const LapSplit({
    required this.lapNumber,
    required this.lapTime,
    required this.lapTimeMs,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.startSampleIndex,
    required this.endSampleIndex,
    required this.topSpeedKmh,
    required this.maxLeanLeftDeg,
    required this.maxLeanRightDeg,
    required this.maxGForce,
    required this.deltaToBest,
    required this.deltaMs,
    required this.isBestLap,
  });

  /// Formatted lap time in mm:ss.ms format (e.g. 1:58.420)
  String get formattedLapTime {
    final minutes = lapTime.inMinutes;
    final seconds = lapTime.inSeconds % 60;
    final millis = lapTime.inMilliseconds % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  /// Formatted delta time relative to the fastest session lap (e.g. +0.42 s or '—' for best)
  String get formattedDelta {
    if (isBestLap) {
      return '—';
    }
    final seconds = deltaMs / 1000.0;
    final sign = seconds >= 0 ? '+' : '';
    return '$sign${seconds.toStringAsFixed(2)} s';
  }

  Map<String, dynamic> toMap() {
    return {
      'lap_number': lapNumber,
      'lap_time_ms': lapTimeMs,
      'start_timestamp_ms': startTimestampMs,
      'end_timestamp_ms': endTimestampMs,
      'start_sample_index': startSampleIndex,
      'end_sample_index': endSampleIndex,
      'top_speed_kmh': topSpeedKmh,
      'max_lean_left_deg': maxLeanLeftDeg,
      'max_lean_right_deg': maxLeanRightDeg,
      'max_g_force': maxGForce,
      'delta_ms': deltaMs,
      'is_best_lap': isBestLap ? 1 : 0,
    };
  }
}
