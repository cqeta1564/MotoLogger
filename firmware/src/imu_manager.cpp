#include "imu_manager.h"
#include <math.h>

static constexpr float RAD_TO_DEG_CONST = 57.29577951308232f;
static constexpr float GRAVITY_CONST    = 9.80665f;

ImuManager::ImuManager()
    : bno_(PIN_IMU_RST),
      is_initialized_(false),
      sample_count_(0),
      roll_offset_deg_(0.0f),
      pitch_offset_deg_(0.0f),
      imu_mux_(portMUX_INITIALIZER_UNLOCKED) {
    memset(&current_sample_, 0, sizeof(current_sample_));
}

bool ImuManager::begin() {
    // 1. Hardware Reset sequence
    pinMode(PIN_IMU_RST, OUTPUT);
    digitalWrite(PIN_IMU_RST, LOW);
    delay(10);
    digitalWrite(PIN_IMU_RST, HIGH);
    delay(50);

    // 2. Configure H_INTN interrupt pin (active LOW)
    pinMode(PIN_IMU_INT, INPUT_PULLUP);

    // 3. Initialize I2C Bus on ESP32-S3 pins
    Wire.begin(PIN_IMU_SDA, PIN_IMU_SCL, I2C_FREQUENCY_HZ);
    delay(20);

    // 4. Initialize BNO085 communication
    if (!bno_.begin_I2C(BNO085_I2C_ADDR, &Wire, PIN_IMU_INT)) {
        return false;
    }

    // 5. Enable high-rate sensor reports
    if (!enableReports()) {
        return false;
    }

    is_initialized_ = true;
    return true;
}

bool ImuManager::enableReports() {
    // 100 Hz Game Rotation Vector (Quaternion fusion: Accel + Gyro, no magnetometer drift)
    if (!bno_.enableReport(SH2_GAME_ROTATION_VECTOR, IMU_REPORT_MICROS)) {
        return false;
    }

    // 100 Hz Linear Acceleration (Gravity compensated)
    if (!bno_.enableReport(SH2_LINEAR_ACCELERATION, IMU_REPORT_MICROS)) {
        return false;
    }

    // 100 Hz Calibrated Gyroscope
    if (!bno_.enableReport(SH2_GYROSCOPE_CALIBRATED, IMU_REPORT_MICROS)) {
        return false;
    }

    return true;
}

void ImuManager::tareZero() {
    portENTER_CRITICAL(&imu_mux_);
    roll_offset_deg_ = current_sample_.roll_deg + roll_offset_deg_;
    pitch_offset_deg_ = current_sample_.pitch_deg + pitch_offset_deg_;
    portEXIT_CRITICAL(&imu_mux_);
}

void ImuManager::setMountingOffsetDeg(float offset_deg) {
    portENTER_CRITICAL(&imu_mux_);
    roll_offset_deg_ = offset_deg;
    portEXIT_CRITICAL(&imu_mux_);
}

ImuSample ImuManager::getLatestSample() {
    ImuSample s;
    portENTER_CRITICAL(&imu_mux_);
    s = current_sample_;
    portEXIT_CRITICAL(&imu_mux_);
    return s;
}

void ImuManager::quaternionToEuler(float qr, float qi, float qj, float qk, 
                                   float& roll_deg, float& pitch_deg, float& yaw_deg) {
    // Standard Z-Y-X Tait-Bryan angles:
    // Roll  (x-axis rotation): Lean Angle
    // Pitch (y-axis rotation): Dive / Squat
    // Yaw   (z-axis rotation): Heading
    
    // Roll (x-axis)
    float sinr_cosp = 2.0f * (qr * qi + qj * qk);
    float cosr_cosp = 1.0f - 2.0f * (qi * qi + qj * qj);
    roll_deg = atan2f(sinr_cosp, cosr_cosp) * RAD_TO_DEG_CONST;

    // Pitch (y-axis)
    float sinp = 2.0f * (qr * qj - qk * qi);
    if (fabsf(sinp) >= 1.0f) {
        pitch_deg = copysignf(90.0f, sinp); // Clamp to 90 degrees if out of range
    } else {
        pitch_deg = asinf(sinp) * RAD_TO_DEG_CONST;
    }

    // Yaw (z-axis)
    float siny_cosp = 2.0f * (qr * qk + qi * qj);
    float cosy_cosp = 1.0f - 2.0f * (qj * qj + qk * qk);
    yaw_deg = atan2f(siny_cosp, cosy_cosp) * RAD_TO_DEG_CONST;
}

bool ImuManager::update(ImuSample& sample) {
    if (!is_initialized_) return false;

    // Check if the BNO085 has pulled H_INTN LOW or has events
    if (bno_.wasReset()) {
        enableReports();
        return false;
    }

    bool new_vector_received = false;

    while (bno_.getSensorEvent(&sensor_value_)) {
        portENTER_CRITICAL(&imu_mux_);
        current_sample_.timestamp_us = esp_timer_get_time();

        switch (sensor_value_.sensorId) {
            case SH2_GAME_ROTATION_VECTOR: {
                float r = sensor_value_.un.gameRotationVector.real;
                float i = sensor_value_.un.gameRotationVector.i;
                float j = sensor_value_.un.gameRotationVector.j;
                float k = sensor_value_.un.gameRotationVector.k;

                float roll, pitch, yaw;
                quaternionToEuler(r, i, j, k, roll, pitch, yaw);

                current_sample_.roll_deg = roll - roll_offset_deg_;
                current_sample_.pitch_deg = pitch - pitch_offset_deg_;
                current_sample_.yaw_deg = yaw;
                current_sample_.accuracy_status = sensor_value_.status;
                new_vector_received = true;
                break;
            }

            case SH2_LINEAR_ACCELERATION:
                // Convert m/s^2 to G
                current_sample_.accel_x_g = sensor_value_.un.linearAcceleration.x / GRAVITY_CONST;
                current_sample_.accel_y_g = sensor_value_.un.linearAcceleration.y / GRAVITY_CONST;
                current_sample_.accel_z_g = sensor_value_.un.linearAcceleration.z / GRAVITY_CONST;
                break;

            case SH2_GYROSCOPE_CALIBRATED:
                // Convert rad/s to deg/s
                current_sample_.gyro_x_dps = sensor_value_.un.gyroscope.x * RAD_TO_DEG_CONST;
                current_sample_.gyro_y_dps = sensor_value_.un.gyroscope.y * RAD_TO_DEG_CONST;
                current_sample_.gyro_z_dps = sensor_value_.un.gyroscope.z * RAD_TO_DEG_CONST;
                break;

            default:
                break;
        }
        portEXIT_CRITICAL(&imu_mux_);
    }

    if (new_vector_received) {
        portENTER_CRITICAL(&imu_mux_);
        sample = current_sample_;
        sample_count_++;
        portEXIT_CRITICAL(&imu_mux_);
        return true;
    }

    return false;
}
