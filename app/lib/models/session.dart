class RideSession {
  final int? id;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;
  final double topSpeedKmh;
  final double maxGForce;
  final double totalDistanceKm;
  final int sampleCount;

  const RideSession({
    this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    this.maxLeanLeftDeg = 0.0,
    this.maxLeanRightDeg = 0.0,
    this.topSpeedKmh = 0.0,
    this.maxGForce = 0.0,
    this.totalDistanceKm = 0.0,
    this.sampleCount = 0,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  RideSession copyWith({
    int? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    double? maxLeanLeftDeg,
    double? maxLeanRightDeg,
    double? topSpeedKmh,
    double? maxGForce,
    double? totalDistanceKm,
    int? sampleCount,
  }) {
    return RideSession(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      maxLeanLeftDeg: maxLeanLeftDeg ?? this.maxLeanLeftDeg,
      maxLeanRightDeg: maxLeanRightDeg ?? this.maxLeanRightDeg,
      topSpeedKmh: topSpeedKmh ?? this.topSpeedKmh,
      maxGForce: maxGForce ?? this.maxGForce,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      sampleCount: sampleCount ?? this.sampleCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'max_lean_left_deg': maxLeanLeftDeg,
      'max_lean_right_deg': maxLeanRightDeg,
      'top_speed_kmh': topSpeedKmh,
      'max_g_force': maxGForce,
      'total_distance_km': totalDistanceKm,
      'sample_count': sampleCount,
    };
  }

  factory RideSession.fromMap(Map<String, dynamic> map) {
    return RideSession(
      id: map['id'] as int?,
      title: map['title'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time'] as String) : null,
      maxLeanLeftDeg: (map['max_lean_left_deg'] as num).toDouble(),
      maxLeanRightDeg: (map['max_lean_right_deg'] as num).toDouble(),
      topSpeedKmh: (map['top_speed_kmh'] as num).toDouble(),
      maxGForce: (map['max_g_force'] as num).toDouble(),
      totalDistanceKm: (map['total_distance_km'] as num).toDouble(),
      sampleCount: map['sample_count'] as int,
    );
  }
}

/// Aggregated telemetry statistics across a riding season or all-time history.
class SeasonStats {
  final int totalRides;
  final double totalDistanceKm;
  final Duration totalDuration;
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;
  final double topSpeedKmh;

  const SeasonStats({
    this.totalRides = 0,
    this.totalDistanceKm = 0.0,
    this.totalDuration = Duration.zero,
    this.maxLeanLeftDeg = 0.0,
    this.maxLeanRightDeg = 0.0,
    this.topSpeedKmh = 0.0,
  });

  factory SeasonStats.fromSessions(List<RideSession> sessions) {
    if (sessions.isEmpty) return const SeasonStats();

    double totalDist = 0.0;
    Duration totalTime = Duration.zero;
    double maxLeft = 0.0;
    double maxRight = 0.0;
    double topSpeed = 0.0;

    for (final s in sessions) {
      totalDist += s.totalDistanceKm;
      totalTime += s.duration;
      if (s.maxLeanLeftDeg > maxLeft) maxLeft = s.maxLeanLeftDeg;
      if (s.maxLeanRightDeg > maxRight) maxRight = s.maxLeanRightDeg;
      if (s.topSpeedKmh > topSpeed) topSpeed = s.topSpeedKmh;
    }

    return SeasonStats(
      totalRides: sessions.length,
      totalDistanceKm: totalDist,
      totalDuration: totalTime,
      maxLeanLeftDeg: maxLeft,
      maxLeanRightDeg: maxRight,
      topSpeedKmh: topSpeed,
    );
  }
}

