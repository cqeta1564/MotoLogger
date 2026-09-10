import 'dart:io';
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

    await file.writeAsString(buffer.toString());
    return file.path;
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
