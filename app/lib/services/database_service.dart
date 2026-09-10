import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/session.dart';
import '../models/fused_sample.dart';
import '../models/can_profile.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;

  DatabaseService._internal();
  DatabaseService.forTesting();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'motologger.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Sessions Table
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        max_lean_left_deg REAL DEFAULT 0.0,
        max_lean_right_deg REAL DEFAULT 0.0,
        top_speed_kmh REAL DEFAULT 0.0,
        max_g_force REAL DEFAULT 0.0,
        total_distance_km REAL DEFAULT 0.0,
        sample_count INTEGER DEFAULT 0
      )
    ''');

    // High-Rate Fused Telemetry Samples Table
    await db.execute('''
      CREATE TABLE samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        recorded_at TEXT NOT NULL,
        lean_angle_deg REAL,
        pitch_deg REAL,
        accel_x_g REAL,
        accel_y_g REAL,
        accel_z_g REAL,
        gyro_x_dps REAL,
        gyro_y_dps REAL,
        gyro_z_dps REAL,
        engine_rpm INTEGER,
        vehicle_speed_kmh INTEGER,
        throttle_pos_pct INTEGER,
        coolant_temp_c INTEGER,
        gear INTEGER,
        battery_voltage REAL,
        latitude REAL,
        longitude REAL,
        altitude REAL,
        gps_speed_kmh REAL,
        bearing REAL,
        gps_accuracy_meters REAL,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');

    // Index for fast session query retrieval
    await db.execute('CREATE INDEX idx_samples_session_id ON samples (session_id)');
  }

  Future<int> startSession(String title) async {
    final db = await database;
    final session = RideSession(
      title: title,
      startTime: DateTime.now(),
    );
    return await db.insert('sessions', session.toMap());
  }

  Future<void> updateSession(RideSession session) async {
    final db = await database;
    await db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<List<RideSession>> getAllSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('sessions', orderBy: 'start_time DESC');
    return List.generate(maps.length, (i) => RideSession.fromMap(maps[i]));
  }

  Future<RideSession?> getSessionById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return RideSession.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertSampleBatch(List<FusedSample> samples) async {
    if (samples.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final s in samples) {
      batch.insert('samples', s.toMap());
    }

    await batch.commit(noResult: true);
  }

  Future<List<FusedSample>> getSamplesForSession(int sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp_ms ASC',
    );
    return List.generate(maps.length, (i) => FusedSample.fromMap(maps[i]));
  }

  // Export Session to RaceRender / MoTeC compatible CSV
  Future<String> exportSessionToCsv(int sessionId) async {
    final session = await getSessionById(sessionId);
    final samples = await getSamplesForSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final dir = await getApplicationDocumentsDirectory();
    final file = File(join(dir.path, 'Ride_Session_${session.id}_${session.startTime.millisecondsSinceEpoch}.csv'));

    final content = generateCsvString(samples: samples);
    await file.writeAsString(content);
    return file.path;
  }

  String generateCsvString({required List<FusedSample> samples}) {
    final buffer = StringBuffer();
    buffer.writeln('timestamp_ms,recorded_at,latitude,longitude,altitude_m,gps_speed_kmh,bearing_deg,'
                   'lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,'
                   'engine_rpm,vehicle_speed_kmh,throttle_pct,coolant_temp_c,gear,battery_v');

    for (final s in samples) {
      buffer.writeln('${s.timestampMs},${s.recordedAt.toIso8601String()},${s.latitude},${s.longitude},'
                     '${s.altitude.toStringAsFixed(1)},${s.gpsSpeedKmh.toStringAsFixed(1)},${s.bearing.toStringAsFixed(1)},'
                     '${s.leanAngleDeg.toStringAsFixed(2)},${s.pitchDeg.toStringAsFixed(2)},'
                     '${s.accelXG.toStringAsFixed(3)},${s.accelYG.toStringAsFixed(3)},${s.accelZG.toStringAsFixed(3)},'
                     '${s.gyroXDps.toStringAsFixed(2)},${s.gyroYDps.toStringAsFixed(2)},${s.gyroZDps.toStringAsFixed(2)},'
                     '${s.engineRpm},${s.vehicleSpeedKmh},${s.throttlePosPct},${s.coolantTempC},${s.gear},'
                     '${s.batteryVoltage.toStringAsFixed(2)}');
    }

    return buffer.toString();
  }

  // Export Session to standard GPX 1.1 with MotoLogger & Garmin extensions
  Future<String> exportSessionToGpx(int sessionId) async {
    final session = await getSessionById(sessionId);
    final samples = await getSamplesForSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final dir = await getApplicationDocumentsDirectory();
    final file = File(join(dir.path, 'Ride_Session_${session.id}_${session.startTime.millisecondsSinceEpoch}.gpx'));

    final content = generateGpxString(session: session, samples: samples);
    await file.writeAsString(content);
    return file.path;
  }

  String generateGpxString({required RideSession session, required List<FusedSample> samples}) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="MotoLogger - Motorcycle Telemetry System"');
    buffer.writeln('  xmlns="http://www.topografix.com/GPX/1/1"');
    buffer.writeln('  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buffer.writeln('  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"');
    buffer.writeln('  xmlns:motologger="http://motologger.org/gpx/1.0"');
    buffer.writeln('  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${_escapeXml(session.title)}</name>');
    buffer.writeln('    <time>${session.startTime.toUtc().toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_escapeXml(session.title)}</name>');
    buffer.writeln('    <trkseg>');

    for (final s in samples) {
      if (s.latitude == 0.0 && s.longitude == 0.0) continue;

      final speedMs = (s.gpsSpeedKmh / 3.6).toStringAsFixed(2);
      buffer.writeln('      <trkpt lat="${s.latitude}" lon="${s.longitude}">');
      buffer.writeln('        <ele>${s.altitude.toStringAsFixed(1)}</ele>');
      buffer.writeln('        <time>${s.recordedAt.toUtc().toIso8601String()}</time>');
      buffer.writeln('        <extensions>');
      buffer.writeln('          <gpxtpx:TrackPointExtension>');
      buffer.writeln('            <gpxtpx:speed>$speedMs</gpxtpx:speed>');
      buffer.writeln('            <gpxtpx:course>${s.bearing.toStringAsFixed(1)}</gpxtpx:course>');
      buffer.writeln('          </gpxtpx:TrackPointExtension>');
      buffer.writeln('          <motologger:lean_angle_deg>${s.leanAngleDeg.toStringAsFixed(2)}</motologger:lean_angle_deg>');
      buffer.writeln('          <motologger:pitch_deg>${s.pitchDeg.toStringAsFixed(2)}</motologger:pitch_deg>');
      buffer.writeln('          <motologger:vehicle_speed_kmh>${s.vehicleSpeedKmh}</motologger:vehicle_speed_kmh>');
      buffer.writeln('          <motologger:engine_rpm>${s.engineRpm}</motologger:engine_rpm>');
      buffer.writeln('          <motologger:throttle_pos_pct>${s.throttlePosPct}</motologger:throttle_pos_pct>');
      buffer.writeln('          <motologger:gear>${s.gear}</motologger:gear>');
      buffer.writeln('          <motologger:coolant_temp_c>${s.coolantTempC}</motologger:coolant_temp_c>');
      buffer.writeln('          <motologger:accel_x_g>${s.accelXG.toStringAsFixed(3)}</motologger:accel_x_g>');
      buffer.writeln('          <motologger:accel_y_g>${s.accelYG.toStringAsFixed(3)}</motologger:accel_y_g>');
      buffer.writeln('          <motologger:accel_z_g>${s.accelZG.toStringAsFixed(3)}</motologger:accel_z_g>');
      buffer.writeln('        </extensions>');
      buffer.writeln('      </trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Pure static parser for raw MicroSD log CSV or exported CSV.
  /// Computes summary metrics, distance, and returns parsed session and sample list.
  static ParsedRideData parseRideCsv({
    required String csvContent,
    String? defaultTitle,
    DateTime? fileTimestamp,
  }) {
    final lines = csvContent.split('\n');
    if (lines.isEmpty) {
      throw const FormatException('Soubor CSV je prázdný.');
    }

    // 1. Locate header line
    int headerIndex = -1;
    List<String> columns = [];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      columns = line.split(',').map((c) => c.trim().toLowerCase()).toList();
      headerIndex = i;
      break;
    }

    if (headerIndex == -1 || columns.isEmpty) {
      throw const FormatException('V CSV souboru nebyla nalezena platná hlavička.');
    }

    // 2. Identify column indices dynamically
    final colTimestamp = columns.indexOf('timestamp_ms');
    final colRecordedAt = columns.indexOf('recorded_at');
    final colLean = columns.indexOf('lean_angle_deg');
    final colPitch = columns.indexOf('pitch_deg');
    final colAccelX = columns.indexOf('accel_x_g');
    final colAccelY = columns.indexOf('accel_y_g');
    final colAccelZ = columns.indexOf('accel_z_g');
    final colGyroX = columns.indexOf('gyro_x_dps');
    final colGyroY = columns.indexOf('gyro_y_dps');
    final colGyroZ = columns.indexOf('gyro_z_dps');
    final colVbat = columns.contains('v_bat')
        ? columns.indexOf('v_bat')
        : columns.indexOf('battery_voltage');
    final colRpm = columns.indexOf('engine_rpm');
    final colSpeed = columns.indexOf('vehicle_speed_kmh');
    final colThrottle = columns.indexOf('throttle_pos_pct');
    final colCoolant = columns.indexOf('coolant_temp_c');
    final colGear = columns.indexOf('gear');
    final colLat = columns.indexOf('latitude');
    final colLon = columns.indexOf('longitude');
    final colAlt = columns.contains('altitude_m')
        ? columns.indexOf('altitude_m')
        : columns.indexOf('altitude');
    final colGpsSpeed = columns.indexOf('gps_speed_kmh');
    final colBearing = columns.contains('bearing_deg')
        ? columns.indexOf('bearing_deg')
        : columns.indexOf('bearing');

    final parsedSamples = <FusedSample>[];
    double maxLeft = 0.0;
    double maxRight = 0.0;
    double topSpeed = 0.0;
    double maxG = 0.0;
    double totalDistanceKm = 0.0;
    int prevTimestampMs = 0;
    double prevSpeedKmh = 0.0;

    DateTime? firstRecordedAt;
    int firstTimestampMs = 0;

    for (int i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split(',');
      if (parts.length < 4) continue;

      double parseD(int idx, [double def = 0.0]) {
        if (idx < 0 || idx >= parts.length) return def;
        return double.tryParse(parts[idx].trim()) ?? def;
      }

      int parseI(int idx, [int def = 0]) {
        if (idx < 0 || idx >= parts.length) return def;
        final d = double.tryParse(parts[idx].trim());
        return d?.round() ?? def;
      }

      final tsMs = colTimestamp >= 0 ? parseI(colTimestamp) : (i * 10);
      if (parsedSamples.isEmpty) {
        firstTimestampMs = tsMs;
      }

      DateTime sampleTime;
      if (colRecordedAt >= 0 && colRecordedAt < parts.length && parts[colRecordedAt].trim().isNotEmpty) {
        sampleTime = DateTime.tryParse(parts[colRecordedAt].trim()) ?? DateTime.now();
        firstRecordedAt ??= sampleTime;
      } else {
        final base = fileTimestamp ?? DateTime.now();
        final offsetFromStart = tsMs - firstTimestampMs;
        sampleTime = base.add(Duration(milliseconds: offsetFromStart));
        firstRecordedAt ??= base;
      }

      final lean = parseD(colLean);
      final pitch = parseD(colPitch);
      final ax = parseD(colAccelX);
      final ay = parseD(colAccelY);
      final az = parseD(colAccelZ, 1.0);
      final gx = parseD(colGyroX);
      final gy = parseD(colGyroY);
      final gz = parseD(colGyroZ);
      final rpm = parseI(colRpm);
      final speed = parseI(colSpeed);
      final tps = parseI(colThrottle);
      final temp = parseI(colCoolant);
      final gear = parseI(colGear);
      final vbat = parseD(colVbat, 12.0);
      final lat = parseD(colLat, 0.0);
      final lon = parseD(colLon, 0.0);
      final alt = parseD(colAlt, 0.0);
      final gpsSpeed = parseD(colGpsSpeed, 0.0);
      final bearing = parseD(colBearing, 0.0);

      // Track extreme metrics
      if (lean < -maxLeft) maxLeft = -lean;
      if (lean > maxRight) maxRight = lean;
      if (speed > topSpeed) topSpeed = speed.toDouble();
      if (gpsSpeed > topSpeed) topSpeed = gpsSpeed;

      final currentG = sqrt(ax * ax + ay * ay);
      if (currentG > maxG) maxG = currentG;

      // Integrate distance over time
      if (parsedSamples.isNotEmpty) {
        final dtSec = (tsMs - prevTimestampMs) / 1000.0;
        if (dtSec > 0 && dtSec < 5.0) {
          final effectiveSpeed = speed > 0 ? speed.toDouble() : gpsSpeed;
          final avgSpd = (effectiveSpeed + prevSpeedKmh) / 2.0;
          totalDistanceKm += (avgSpd * dtSec) / 3600.0;
        }
      }
      prevTimestampMs = tsMs;
      prevSpeedKmh = speed > 0 ? speed.toDouble() : gpsSpeed;

      parsedSamples.add(FusedSample(
        sessionId: 0,
        timestampMs: tsMs,
        recordedAt: sampleTime,
        leanAngleDeg: lean,
        pitchDeg: pitch,
        accelXG: ax,
        accelYG: ay,
        accelZG: az,
        gyroXDps: gx,
        gyroYDps: gy,
        gyroZDps: gz,
        engineRpm: rpm,
        vehicleSpeedKmh: speed,
        throttlePosPct: tps,
        coolantTempC: temp,
        gear: gear,
        batteryVoltage: vbat,
        latitude: lat,
        longitude: lon,
        altitude: alt,
        gpsSpeedKmh: gpsSpeed,
        bearing: bearing,
        gpsAccuracyMeters: lat != 0.0 ? 5.0 : 0.0,
      ));
    }

    if (parsedSamples.isEmpty) {
      throw const FormatException('V CSV souboru nebyly nalezeny žádné telemetrické vzorky.');
    }

    final start = firstRecordedAt ?? DateTime.now();
    final end = parsedSamples.last.recordedAt;
    final finalTitle = defaultTitle ?? 'Importovaná jízda (${start.day}.${start.month}.${start.year} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')})';

    final session = RideSession(
      title: finalTitle,
      startTime: start,
      endTime: end,
      maxLeanLeftDeg: maxLeft,
      maxLeanRightDeg: maxRight,
      topSpeedKmh: topSpeed,
      maxGForce: maxG,
      totalDistanceKm: double.parse(totalDistanceKm.toStringAsFixed(2)),
      sampleCount: parsedSamples.length,
    );

    return ParsedRideData(session: session, samples: parsedSamples);
  }

  /// Imports a ride session from raw MicroSD log CSV (LOG_XXXX.CSV) or exported CSV.
  /// Parses all telemetry rows, computes peak statistics, and bulk-inserts all samples into SQLite.
  Future<RideSession> importRideFromCsv({
    required String csvContent,
    String? defaultTitle,
    DateTime? fileTimestamp,
  }) async {
    final parsed = parseRideCsv(
      csvContent: csvContent,
      defaultTitle: defaultTitle,
      fileTimestamp: fileTimestamp,
    );

    final db = await database;
    final sessionId = await db.insert('sessions', parsed.session.toMap());
    final savedSession = parsed.session.copyWith(id: sessionId);

    final batch = db.batch();
    for (final sample in parsed.samples) {
      batch.insert('samples', sample.copyWith(sessionId: sessionId).toMap());
    }
    await batch.commit(noResult: true);

    return savedSession;
  }

  /// Calculates aggregated season statistics across all rides or for a given year.
  Future<SeasonStats> getSeasonStats({int? year}) async {
    final allSessions = await getAllSessions();
    final filtered = year == null
        ? allSessions
        : allSessions.where((s) => s.startTime.year == year).toList();
    return SeasonStats.fromSessions(filtered);
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('samples', where: 'session_id = ?', whereArgs: [id]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  // Key-Value App Settings Storage (Persistent)
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  Future<void> removeSetting(String key) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  // Bike CAN Mapping Profiles Storage
  Future<void> _ensureBikeProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bike_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        can_baudrate INTEGER NOT NULL,
        signals_json TEXT NOT NULL,
        raw_ai_json TEXT
      )
    ''');
  }

  Future<void> saveBikeProfile(BikeProfile profile) async {
    final db = await database;
    await _ensureBikeProfilesTable(db);
    await db.insert(
      'bike_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BikeProfile>> getAllBikeProfiles() async {
    final db = await database;
    await _ensureBikeProfilesTable(db);
    final List<Map<String, dynamic>> maps = await db.query('bike_profiles', orderBy: 'created_at DESC');
    return maps.map((m) => BikeProfile.fromMap(m)).toList();
  }

  Future<BikeProfile?> getBikeProfileById(String id) async {
    final db = await database;
    await _ensureBikeProfilesTable(db);
    final maps = await db.query('bike_profiles', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return BikeProfile.fromMap(maps.first);
    }
    return null;
  }

  Future<void> deleteBikeProfile(String id) async {
    final db = await database;
    await _ensureBikeProfilesTable(db);
    await db.delete('bike_profiles', where: 'id = ?', whereArgs: [id]);
  }
}

/// Parsed ride session data and samples extracted from a CSV file.
class ParsedRideData {
  final RideSession session;
  final List<FusedSample> samples;

  const ParsedRideData({
    required this.session,
    required this.samples,
  });
}

