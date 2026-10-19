#pragma once

#include <Arduino.h>

/**
 * @file types.h
 * @brief Common telemetry data structures, enums, and BLE binary packets.
 */

// ==============================================================================
// Power Management States
// ==============================================================================
enum class PowerState : uint8_t {
    BOOTING,                // Initial power-up, evaluating battery
    RUNNING,                // Engine active / alternator charging (normal operation)
    COUNTDOWN_TO_SHUTDOWN,  // Ignition turned off, countdown active
    SHUTTING_DOWN           // Finalizing logs, unmounting SD, dropping power latch
};

// ==============================================================================
// CAN Message Container
// ==============================================================================
struct CanFrame {
    uint64_t timestamp_us;
    uint32_t id;
    uint8_t  dlc;
    uint8_t  data[8];
    bool     is_extended;
    bool     is_rtr;
};

// ==============================================================================
// Motorcycle CAN Signal & Profile Configuration (Stored in NVS Preferences)
// ==============================================================================
enum class CanSignalType : uint8_t {
    RPM      = 0,
    SPEED    = 1,
    THROTTLE = 2,
    GEAR     = 3,
    COOLANT  = 4
};

struct __attribute__((packed)) CanSignalConfig {
    uint32_t can_id;        // CAN arbitration ID (e.g. 0x1F0)
    uint8_t  start_byte;    // Start byte in payload (0..7)
    uint8_t  length_bytes;  // Length in bytes (1 or 2)
    uint8_t  is_big_endian; // 1 = Big Endian, 0 = Little Endian
    uint8_t  is_active;     // 1 = Active, 0 = Disabled
    float    multiplier;    // Scale factor (e.g. 0.05f)
    float    offset;        // Additive offset (e.g. -40.0f)
};

struct __attribute__((packed)) EspBikeCanProfile {
    uint32_t magic;          // 0x4D4F544F ('MOTO')
    uint8_t  profile_active; // 1 = Custom mapping active, 0 = Standard OBD
    uint8_t  reserved;
    uint16_t baudrate_kbps;  // 250, 500 (default), or 1000 kbps
    CanSignalConfig rpm;
    CanSignalConfig speed;
    CanSignalConfig throttle;
    CanSignalConfig gear;
    CanSignalConfig coolant;
};

// ==============================================================================
// IMU 9-DoF Telemetry Sample (BNO085)
// ==============================================================================
struct ImuSample {
    uint64_t timestamp_us;
    
    // Euler angles in degrees (Game Rotation Vector)
    float roll_deg;         // Motorcycle Lean Angle (+ right, - left)
    float pitch_deg;        // Motorcycle Pitch (+ wheelie/accel, - braking dive)
    float yaw_deg;          // Relative Heading
    
    // Linear Acceleration (gravity compensated) in G (1G ~ 9.81 m/s^2)
    float accel_x_g;        // Longitudinal acceleration (+ forward, - braking)
    float accel_y_g;        // Lateral acceleration
    float accel_z_g;        // Vertical acceleration
    
    // Calibrated Angular Velocity in degrees/sec
    float gyro_x_dps;       // Roll rate
    float gyro_y_dps;       // Pitch rate
    float gyro_z_dps;       // Yaw rate

    uint8_t accuracy_status; // Sensor report accuracy (0 = Unreliable, 3 = High)
};

// ==============================================================================
// Decoded OBD-II / Engine Telemetry
// ==============================================================================
struct ObdTelemetry {
    uint32_t last_update_ms;
    uint16_t engine_rpm;
    uint8_t  vehicle_speed_kmh;
    float    throttle_pos_pct;
    int16_t  coolant_temp_c;
    int8_t   gear;                  // -1 = unknown, 0 = neutral, 1..6 = gears
    bool     data_valid;
};

// ==============================================================================
// Unified Telemetry Record for CSV Logging (100 Hz synchronized)
// ==============================================================================
struct TelemetryRecord {
    uint32_t timestamp_ms;
    
    // IMU Dynamics
    float lean_angle_deg;
    float pitch_deg;
    float accel_x_g;
    float accel_y_g;
    float accel_z_g;
    float gyro_x_dps;
    float gyro_y_dps;
    float gyro_z_dps;
    
    // Vehicle & Powertrain
    float    battery_voltage;
    uint16_t engine_rpm;
    uint8_t  vehicle_speed_kmh;
    float    throttle_pos_pct;
    int16_t  coolant_temp_c;
    int8_t   gear;
};

// ==============================================================================
// OBD-II Diagnostic Trouble Code (DTC) Entry
// ==============================================================================
struct ObdDtcEntry {
    char    code[6];        // Standard 5-char SAE J2012 code e.g. "P0115" + null terminator
    uint8_t is_pending;     // 0 = Stored (Mode 03), 1 = Pending (Mode 07)
};

// ==============================================================================
// Telemetry Status Flags Bitmask (BleTelemetryPacket::status_flags)
// ==============================================================================
constexpr uint8_t STATUS_FLAG_SD_READY           = (1 << 0);
constexpr uint8_t STATUS_FLAG_ENGINE_RUNNING     = (1 << 1);
constexpr uint8_t STATUS_FLAG_SHUTDOWN_COUNTDOWN = (1 << 2);
constexpr uint8_t STATUS_FLAG_IMU_READY          = (1 << 3);
constexpr uint8_t STATUS_FLAG_DIAG_ACTIVE        = (1 << 4); // 1 = Active CAN TX (Diagnostics), 0 = Listen-Only RX

// ==============================================================================
// Packed Binary BLE Telemetry Packet (Transmitted at 25 Hz to Smartphone)
// 29 bytes total (28 bytes base payload + 1 byte status_flags at offset 28)
// ==============================================================================
struct __attribute__((packed)) BleTelemetryPacket {
    uint32_t timestamp_ms;       // Offset 0..3:   Monotonic timestamp (ms)
    int16_t  lean_angle_x10;     // Offset 4..5:   Roll * 10 (-1800 .. +1800 -> +/- 180.0 deg)
    int16_t  pitch_x10;          // Offset 6..7:   Pitch * 10 (-900 .. +900 -> +/- 90.0 deg)
    int16_t  accel_x_mg;         // Offset 8..9:   Longitudinal G * 1000 (+1000 = +1.0G accel)
    int16_t  accel_y_mg;         // Offset 10..11: Lateral G * 1000
    int16_t  accel_z_mg;         // Offset 12..13: Vertical G * 1000
    int16_t  gyro_x_dps_x10;     // Offset 14..15: Roll rate * 10 (deg/s * 10)
    int16_t  gyro_y_dps_x10;     // Offset 16..17: Pitch rate * 10 (deg/s * 10)
    int16_t  gyro_z_dps_x10;     // Offset 18..19: Yaw rate * 10 (deg/s * 10)
    uint16_t engine_rpm;         // Offset 20..21: RPM (0 - 25000)
    uint8_t  vehicle_speed_kmh;  // Offset 22:     Speed (0 - 255 km/h)
    uint8_t  throttle_pos_pct;   // Offset 23:     Throttle (0 - 100 %)
    int8_t   coolant_temp_c;     // Offset 24:     Engine coolant temp (-40 .. +127 C)
    int8_t   gear;               // Offset 25:     Calculated gear (-1 = unknown, 0 = N, 1..6)
    uint16_t battery_mv;         // Offset 26..27: Battery voltage (e.g. 14250 = 14.25 V)
    uint8_t  status_flags;       // Offset 28:     Bit 0: SD active, Bit 1: Engine run, Bit 2: Countdown, Bit 3: IMU ok
};

static_assert(sizeof(BleTelemetryPacket) == 29, "BleTelemetryPacket must be exactly 29 bytes");
static_assert(sizeof(CanSignalConfig) == 16, "CanSignalConfig must be exactly 16 bytes");

// ==============================================================================
// Asynchronous BLE Command Event (Decouples NimBLE GATT callback from NVS/SD I/O)
// ==============================================================================
struct BleCommandEvent {
    uint8_t command_id;
    uint8_t length;
    uint8_t payload[32];
};

