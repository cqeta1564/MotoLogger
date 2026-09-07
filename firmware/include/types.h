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
// Packed Binary BLE Telemetry Packet (Transmitted at 25 Hz to Smartphone)
// Exactly 28 bytes - zero parsing overhead on Flutter / iOS / Android!
// ==============================================================================
struct __attribute__((packed)) BleTelemetryPacket {
    uint32_t timestamp_ms;       // Monotonic timestamp (ms)
    int16_t  lean_angle_x10;     // Roll * 10 (-1800 .. +1800 -> +/- 180.0 deg)
    int16_t  pitch_x10;          // Pitch * 10 (-900 .. +900 -> +/- 90.0 deg)
    int16_t  accel_x_mg;         // Longitudinal G * 1000 (+1000 = +1.0G accel)
    int16_t  accel_y_mg;         // Lateral G * 1000
    int16_t  accel_z_mg;         // Vertical G * 1000
    int16_t  gyro_x_dps_x10;     // Roll rate * 10 (deg/s * 10)
    int16_t  gyro_y_dps_x10;     // Pitch rate * 10 (deg/s * 10)
    int16_t  gyro_z_dps_x10;     // Yaw rate * 10 (deg/s * 10)
    uint16_t engine_rpm;         // RPM (0 - 20000)
    uint8_t  vehicle_speed_kmh;  // Speed (0 - 255 km/h)
    uint8_t  throttle_pos_pct;   // Throttle (0 - 100 %)
    int8_t   coolant_temp_c;     // Engine coolant temp (-40 .. +150 C)
    int8_t   gear;               // Calculated gear (-1 = unknown, 0 = N, 1..6)
    uint16_t battery_mv;         // Battery voltage (e.g. 14250 = 14.25 V)
    uint8_t  status_flags;       // Bit 0: SD active, Bit 1: Engine run, Bit 2: Countdown, Bit 3: IMU ok
};
