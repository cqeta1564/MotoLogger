import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/fused_sample.dart';
import '../models/lap_split.dart';

typedef TrackCircuit = CircuitGate;

class CircuitGate {
  final String name;
  final double centerLat;
  final double centerLon;
  final double p1Lat;
  final double p1Lon;
  final double p2Lat;
  final double p2Lon;
  final double expectedHeadingDeg;

  const CircuitGate({
    required this.name,
    required this.centerLat,
    required this.centerLon,
    required this.p1Lat,
    required this.p1Lon,
    required this.p2Lat,
    required this.p2Lon,
    required this.expectedHeadingDeg,
  });
}

class GateCrossing {
  final int timestampMs;
  final int sampleIndex;
  final double u; // Interpolation ratio between sampleIndex - 1 and sampleIndex

  const GateCrossing({
    required this.timestampMs,
    required this.sampleIndex,
    required this.u,
  });
}

class LapTimerService {
  // Pre-configured official race circuits
  static const List<CircuitGate> knownCircuits = [
    // Automotodrom Brno (Masarykův okruh)
    // S/F straight runs approximately East -> West (bearing ~268°)
    CircuitGate(
      name: 'Automotodrom Brno',
      centerLat: 49.203875,
      centerLon: 16.444250,
      p1Lat: 49.204050,
      p1Lon: 16.444250,
      p2Lat: 49.203700,
      p2Lon: 16.444250,
      expectedHeadingDeg: 268.0,
    ),
    // Autodrom Most
    // S/F straight runs approximately WSW -> ENE (bearing ~70°)
    CircuitGate(
      name: 'Autodrom Most',
      centerLat: 50.518600,
      centerLon: 13.606800,
      p1Lat: 50.518800,
      p1Lon: 13.606600,
      p2Lat: 50.518400,
      p2Lon: 13.607000,
      expectedHeadingDeg: 70.0,
    ),
    // Slovakia Ring
    // S/F straight runs West -> East (bearing ~95°)
    CircuitGate(
      name: 'Slovakia Ring',
      centerLat: 48.055800,
      centerLon: 17.568400,
      p1Lat: 48.056000,
      p1Lon: 17.568400,
      p2Lat: 48.055600,
      p2Lon: 17.568400,
      expectedHeadingDeg: 95.0,
    ),
  ];

  /// Resolves which circuit the session was recorded at, or generates a dynamic gate
  /// based on the initial trajectory of the ride.
  CircuitGate? resolveCircuit(List<FusedSample> samples) {
    if (samples.isEmpty) return null;

    // Check proximity to known circuits (within 500 meters of S/F line)
    for (final circuit in knownCircuits) {
      for (final s in samples) {
        if (s.latitude == 0.0 && s.longitude == 0.0) continue;
        final dist = Geolocator.distanceBetween(
          s.latitude,
          s.longitude,
          circuit.centerLat,
          circuit.centerLon,
        );
        if (dist <= 500.0) {
          return circuit;
        }
      }
    }

    // Fallback: Generate dynamic gate at the starting point of the closed circuit
    for (int i = 0; i < samples.length - 1; i++) {
      final s = samples[i];
      if (s.latitude == 0.0 && s.longitude == 0.0) continue;
      final speed = s.vehicleSpeedKmh > 0 ? s.vehicleSpeedKmh.toDouble() : s.gpsSpeedKmh;
      if (speed >= 10.0) {
        final next = samples[i + 1];
        double heading = s.bearing;
        if (heading == 0.0 && next.latitude != s.latitude) {
          heading = Geolocator.bearingBetween(
            s.latitude,
            s.longitude,
            next.latitude,
            next.longitude,
          );
          if (heading < 0) heading += 360.0;
        }

        return _createPerpendicularGate(
          name: 'Uzavřený okruh',
          centerLat: s.latitude,
          centerLon: s.longitude,
          headingDeg: heading,
          halfWidthMeters: 30.0,
        );
      }
    }

    return null;
  }

  /// Calculates a perpendicular gate across track heading
  static CircuitGate createCustomCircuitFromPosition({
    required double lat,
    required double lon,
    required double headingDeg,
    String name = 'Vlastní okruh',
    double halfWidthMeters = 30.0,
  }) {
    final perpHeadingRad = (headingDeg + 90.0) * (pi / 180.0);
    // 1 deg latitude ~ 111,320 meters
    final dLat = (halfWidthMeters * cos(perpHeadingRad)) / 111320.0;
    final dLon = (halfWidthMeters * sin(perpHeadingRad)) /
        (111320.0 * cos(lat * (pi / 180.0)));

    return CircuitGate(
      name: name,
      centerLat: lat,
      centerLon: lon,
      p1Lat: lat + dLat,
      p1Lon: lon + dLon,
      p2Lat: lat - dLat,
      p2Lon: lon - dLon,
      expectedHeadingDeg: headingDeg,
    );
  }

  /// Calculates a perpendicular gate across track heading (instance helper)
  CircuitGate _createPerpendicularGate({
    required String name,
    required double centerLat,
    required double centerLon,
    required double headingDeg,
    required double halfWidthMeters,
  }) {
    return createCustomCircuitFromPosition(
      name: name,
      lat: centerLat,
      lon: centerLon,
      headingDeg: headingDeg,
      halfWidthMeters: halfWidthMeters,
    );
  }

  /// Inkrementální kontrola průjezdu cílovou čárou mezi dvěma sousedními vzorky
  static GateCrossing? checkSingleSegmentCrossing(
    FusedSample prev,
    FusedSample curr,
    CircuitGate gate, {
    int lastCrossMs = -999999,
    int cooldownMs = 15000,
    int sampleIndex = 0,
  }) {
    if (curr.latitude == 0.0 && curr.longitude == 0.0) return null;
    if (prev.latitude == 0.0 && prev.longitude == 0.0) return null;

    final x1 = prev.longitude;
    final y1 = prev.latitude;
    final x2 = curr.longitude;
    final y2 = curr.latitude;

    final gx1 = gate.p1Lon;
    final gy1 = gate.p1Lat;
    final gx2 = gate.p2Lon;
    final gy2 = gate.p2Lat;

    // 2D Line Segment Intersection Algorithm
    final det = (x2 - x1) * (gy2 - gy1) - (y2 - y1) * (gx2 - gx1);
    if (det.abs() < 1e-12) return null; // Parallel segments

    final u = ((gx1 - x1) * (gy2 - gy1) - (gy1 - y1) * (gx2 - gx1)) / det;
    final v = ((gx1 - x1) * (y2 - y1) - (gy1 - y1) * (x2 - x1)) / det;

    if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
      // Segments intersect! Verify direction of travel
      double segHeading = Geolocator.bearingBetween(y1, x1, y2, x2);
      if (segHeading < 0) segHeading += 360.0;

      double segDiff =
          (segHeading - gate.expectedHeadingDeg + 180.0) % 360.0 - 180.0;
      if (segDiff < -180.0) segDiff += 360.0;

      double heading = curr.bearing != 0.0 ? curr.bearing : segHeading;
      double diff =
          (heading - gate.expectedHeadingDeg + 180.0) % 360.0 - 180.0;
      if (diff < -180.0) diff += 360.0;

      // Must travel forward within +/- 90 degrees of track direction
      if (segDiff.abs() <= 90.0 && diff.abs() <= 90.0) {
        final t1 = prev.timestampMs;
        final t2 = curr.timestampMs;
        final crossTimeMs = t1 + (u * (t2 - t1)).round();

        if (crossTimeMs - lastCrossMs >= cooldownMs) {
          return GateCrossing(
            timestampMs: crossTimeMs,
            sampleIndex: sampleIndex,
            u: u,
          );
        }
      }
    }
    return null;
  }

  /// Finds all finish line crossing events in the sample stream
  List<GateCrossing> detectCrossings(List<FusedSample> samples,
      {CircuitGate? gate}) {
    if (samples.length < 2) return [];
    final activeGate = gate ?? resolveCircuit(samples);
    if (activeGate == null) return [];

    final List<GateCrossing> crossings = [];
    int lastCrossMs = -999999;
    const int cooldownMs = 15000; // Minimum 15 seconds cooldown between lap triggers

    for (int i = 1; i < samples.length; i++) {
      final prev = samples[i - 1];
      final curr = samples[i];

      final crossing = checkSingleSegmentCrossing(
        prev,
        curr,
        activeGate,
        lastCrossMs: lastCrossMs,
        cooldownMs: cooldownMs,
        sampleIndex: i,
      );

      if (crossing != null) {
        crossings.add(crossing);
        lastCrossMs = crossing.timestampMs;
      }
    }

    return crossings;
  }

  /// Detects all completed laps from recorded telemetry samples
  List<LapSplit> detectLaps(List<FusedSample> samples, {CircuitGate? gate}) {
    final crossings = detectCrossings(samples, gate: gate);
    if (crossings.length < 2) return [];

    final List<LapSplit> rawLaps = [];
    int bestLapMs = 999999999;
    const int maxCircuitLapDurationMs = 720000; // 12 minutes max for a closed-circuit lap

    for (int i = 1; i < crossings.length; i++) {
      final startCrossing = crossings[i - 1];
      final endCrossing = crossings[i];

      final lapTimeMs = endCrossing.timestampMs - startCrossing.timestampMs;
      if (lapTimeMs <= 0 || lapTimeMs > maxCircuitLapDurationMs) {
        continue;
      }
      if (lapTimeMs < bestLapMs) {
        bestLapMs = lapTimeMs;
      }

      // Calculate peak dynamics across the lap's sample slice
      double topSpd = 0.0;
      double maxLeft = 0.0;
      double maxRight = 0.0;
      double maxG = 0.0;

      final startIdx = startCrossing.sampleIndex;
      final endIdx = endCrossing.sampleIndex;

      for (int k = startIdx; k <= endIdx && k < samples.length; k++) {
        final s = samples[k];
        final spd = s.vehicleSpeedKmh > 0 ? s.vehicleSpeedKmh.toDouble() : s.gpsSpeedKmh;
        if (spd > topSpd) topSpd = spd;
        if (s.leanAngleDeg < maxLeft) maxLeft = s.leanAngleDeg;
        if (s.leanAngleDeg > maxRight) maxRight = s.leanAngleDeg;

        final g = sqrt(s.accelXG * s.accelXG + s.accelYG * s.accelYG);
        if (g > maxG) maxG = g;
      }

      rawLaps.add(LapSplit(
        lapNumber: rawLaps.length + 1,
        lapTime: Duration(milliseconds: lapTimeMs),
        lapTimeMs: lapTimeMs,
        startTimestampMs: startCrossing.timestampMs,
        endTimestampMs: endCrossing.timestampMs,
        startSampleIndex: startIdx,
        endSampleIndex: endIdx,
        topSpeedKmh: topSpd,
        maxLeanLeftDeg: maxLeft,
        maxLeanRightDeg: maxRight,
        maxGForce: maxG,
        deltaToBest: Duration.zero,
        deltaMs: 0,
        isBestLap: false,
      ));
    }

    // Finalize deltas relative to best lap
    final List<LapSplit> finalLaps = [];
    for (final lap in rawLaps) {
      final isBest = lap.lapTimeMs == bestLapMs;
      final delta = lap.lapTimeMs - bestLapMs;

      finalLaps.add(LapSplit(
        lapNumber: lap.lapNumber,
        lapTime: lap.lapTime,
        lapTimeMs: lap.lapTimeMs,
        startTimestampMs: lap.startTimestampMs,
        endTimestampMs: lap.endTimestampMs,
        startSampleIndex: lap.startSampleIndex,
        endSampleIndex: lap.endSampleIndex,
        topSpeedKmh: lap.topSpeedKmh,
        maxLeanLeftDeg: lap.maxLeanLeftDeg,
        maxLeanRightDeg: lap.maxLeanRightDeg,
        maxGForce: lap.maxGForce,
        deltaToBest: Duration(milliseconds: delta),
        deltaMs: delta,
        isBestLap: isBest,
      ));
    }

    return finalLaps;
  }

  /// Returns indices of samples that represent finish line beacon triggers
  Set<int> getBeaconSampleIndices(List<FusedSample> samples, {CircuitGate? gate}) {
    final crossings = detectCrossings(samples, gate: gate);
    return crossings.map((c) => c.sampleIndex).toSet();
  }
}
