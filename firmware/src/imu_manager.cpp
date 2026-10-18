#include "imu_manager.h"
#include <math.h>
#include <Preferences.h>

static constexpr float RAD_TO_DEG_CONST = 57.29577951308232f;
static constexpr float GRAVITY_CONST    = 9.80665f;

ImuManager::ImuManager()
    : spi_imu_(HSPI),
      spi_bus_initialized_(false),
      bno_(PIN_IMU_RST),
      is_initialized_(false),
      sample_count_(0),
      raw_roll_deg_(0.0f),
      raw_pitch_deg_(0.0f),
      roll_offset_deg_(0.0f),
      pitch_offset_deg_(0.0f),
      imu_mux_(portMUX_INITIALIZER_UNLOCKED),
      last_reconnect_attempt_ms_(0),
      last_event_ms_(0) {
    memset(&current_sample_, 0, sizeof(current_sample_));
    memset(&sensor_value_, 0, sizeof(sensor_value_));
}

float ImuManager::normalizeAngle180(float angle_deg) {
    if (!isfinite(angle_deg)) return 0.0f;
    while (angle_deg > 180.0f)  angle_deg -= 360.0f;
    while (angle_deg < -180.0f) angle_deg += 360.0f;
    return angle_deg;
}

float ImuManager::clampPitch90(float pitch_deg) {
    if (!isfinite(pitch_deg)) return 0.0f;
    if (pitch_deg > 90.0f)  return 90.0f;
    if (pitch_deg < -90.0f) return -90.0f;
    return pitch_deg;
}

bool ImuManager::initSensorHardware() {
    if (bno_.begin_SPI(PIN_IMU_CS, PIN_IMU_INT, &spi_imu_)) {
        if (enableReports()) {
            return true;
        }
    }
    return false;
}

bool ImuManager::begin() {
    last_reconnect_attempt_ms_ = millis();

    // 1. Always load saved calibration offsets from NVS first
    loadCalibrationFromNvs();

    // 2. Hardware CS pin setup (inactive HIGH)
    pinMode(PIN_IMU_CS, OUTPUT);
    digitalWrite(PIN_IMU_CS, HIGH);

    // 3. Configure H_INTN interrupt pin (active LOW)
    pinMode(PIN_IMU_INT, INPUT_PULLUP);

    // 4. Initialize dedicated HSPI bus for IMU
    if (!spi_bus_initialized_) {
        spi_imu_.begin(PIN_IMU_SCK, PIN_IMU_MISO, PIN_IMU_MOSI, PIN_IMU_CS);
        spi_bus_initialized_ = true;
    }

    // 5. Hardware Reset sequence
    pinMode(PIN_IMU_RST, OUTPUT);
    digitalWrite(PIN_IMU_RST, LOW);
    delay(10);
    digitalWrite(PIN_IMU_RST, HIGH);
    delay(50);

    // 6. Initialize BNO085 SPI communication and enable high-rate reports
    if (!initSensorHardware()) {
        is_initialized_.store(false, std::memory_order_release);
        return false;
    }

    last_event_ms_ = millis();
    is_initialized_.store(true, std::memory_order_release);
    return true;
}

bool ImuManager::tryReconnect() {
    last_reconnect_attempt_ms_ = millis();

    // Re-assert CS inactive HIGH
    pinMode(PIN_IMU_CS, OUTPUT);
    digitalWrite(PIN_IMU_CS, HIGH);

    // Pulse hardware reset briefly
    digitalWrite(PIN_IMU_RST, LOW);
    delay(10);
    digitalWrite(PIN_IMU_RST, HIGH);
    delay(40);

    if (initSensorHardware()) {
        last_event_ms_ = millis();
        is_initialized_.store(true, std::memory_order_release);
        Serial.println("\n[IMU] BNO085 recovered via HSPI! Sensor running at 100 Hz.");
        return true;
    }

    return false;
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
    roll_offset_deg_  = raw_roll_deg_;
    pitch_offset_deg_ = raw_pitch_deg_;
    current_sample_.roll_deg  = 0.0f;
    current_sample_.pitch_deg = 0.0f;
    portEXIT_CRITICAL(&imu_mux_);
    saveCalibrationToNvs();
}

void ImuManager::setRollOffset(float offset_deg) {
    if (!isfinite(offset_deg)) return;
    portENTER_CRITICAL(&imu_mux_);
    roll_offset_deg_ = normalizeAngle180(offset_deg);
    current_sample_.roll_deg = normalizeAngle180(raw_roll_deg_ - roll_offset_deg_);
    portEXIT_CRITICAL(&imu_mux_);
    saveCalibrationToNvs();
}

float ImuManager::getRollOffset() const {
    float offset;
    portENTER_CRITICAL(&imu_mux_);
    offset = roll_offset_deg_;
    portEXIT_CRITICAL(&imu_mux_);
    return offset;
}

void ImuManager::saveCalibrationToNvs() {
    float roll_off, pitch_off;
    portENTER_CRITICAL(&imu_mux_);
    roll_off  = roll_offset_deg_;
    pitch_off = pitch_offset_deg_;
    portEXIT_CRITICAL(&imu_mux_);

    Preferences prefs;
    if (prefs.begin("motologger", false)) {
        prefs.putFloat("roll_offset", roll_off);
        prefs.putFloat("pitch_offset", pitch_off);
        prefs.end();
        Serial.printf("[IMU] Calibration saved to NVS: roll=%.2f deg, pitch=%.2f deg\n", 
                      roll_off, pitch_off);
    } else {
        Serial.println("[IMU] Failed to open NVS for writing calibration!");
    }
}

void ImuManager::loadCalibrationFromNvs() {
    Preferences prefs;
    if (prefs.begin("motologger", true)) {
        float roll_off  = prefs.getFloat("roll_offset", 0.0f);
        float pitch_off = prefs.getFloat("pitch_offset", 0.0f);
        prefs.end();

        portENTER_CRITICAL(&imu_mux_);
        roll_offset_deg_  = isfinite(roll_off) ? normalizeAngle180(roll_off) : 0.0f;
        pitch_offset_deg_ = isfinite(pitch_off) ? clampPitch90(pitch_off) : 0.0f;
        portEXIT_CRITICAL(&imu_mux_);

        Serial.printf("[IMU] Calibration loaded from NVS: roll=%.2f deg, pitch=%.2f deg\n", 
                      roll_offset_deg_, pitch_offset_deg_);
    } else {
        Serial.println("[IMU] No previous calibration in NVS (using default 0.0 deg).");
    }
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
    // Normalize quaternion to guard against SPI bit-corruption or NaN propagation
    float norm_sq = qr * qr + qi * qi + qj * qj + qk * qk;
    if (!isfinite(norm_sq) || norm_sq < 1e-6f) {
        roll_deg  = 0.0f;
        pitch_deg = 0.0f;
        yaw_deg   = 0.0f;
        return;
    }
    float inv_norm = 1.0f / sqrtf(norm_sq);
    qr *= inv_norm;
    qi *= inv_norm;
    qj *= inv_norm;
    qk *= inv_norm;

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
    uint32_t now = millis();

    if (!is_initialized_.load(std::memory_order_acquire)) {
        if (now - last_reconnect_attempt_ms_ >= 2500) {
            tryReconnect();
        }
        return false;
    }

    // Re-enable reports automatically if BNO085 signals an internal reset
    if (bno_.wasReset()) {
        if (!enableReports()) {
            is_initialized_.store(false, std::memory_order_release);
        }
        return false;
    }

    bool new_vector_received = false;
    uint8_t events_processed = 0;

    // Drain up to 16 queued SHTP reports per 10 ms cycle to prevent loop starvation
    while (events_processed < 16 && bno_.getSensorEvent(&sensor_value_)) {
        events_processed++;
        last_event_ms_ = now;

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

                raw_roll_deg_  = roll;
                raw_pitch_deg_ = pitch;

                current_sample_.roll_deg  = normalizeAngle180(roll - roll_offset_deg_);
                current_sample_.pitch_deg = clampPitch90(pitch - pitch_offset_deg_);
                current_sample_.yaw_deg   = yaw;
                current_sample_.accuracy_status = sensor_value_.status;
                new_vector_received = true;
                break;
            }

            case SH2_LINEAR_ACCELERATION: {
                float ax = sensor_value_.un.linearAcceleration.x / GRAVITY_CONST;
                float ay = sensor_value_.un.linearAcceleration.y / GRAVITY_CONST;
                float az = sensor_value_.un.linearAcceleration.z / GRAVITY_CONST;
                if (isfinite(ax) && isfinite(ay) && isfinite(az)) {
                    current_sample_.accel_x_g = ax;
                    current_sample_.accel_y_g = ay;
                    current_sample_.accel_z_g = az;
                }
                break;
            }

            case SH2_GYROSCOPE_CALIBRATED: {
                float gx = sensor_value_.un.gyroscope.x * RAD_TO_DEG_CONST;
                float gy = sensor_value_.un.gyroscope.y * RAD_TO_DEG_CONST;
                float gz = sensor_value_.un.gyroscope.z * RAD_TO_DEG_CONST;
                if (isfinite(gx) && isfinite(gy) && isfinite(gz)) {
                    current_sample_.gyro_x_dps = gx;
                    current_sample_.gyro_y_dps = gy;
                    current_sample_.gyro_z_dps = gz;
                }
                break;
            }

            default:
                break;
        }
        portEXIT_CRITICAL(&imu_mux_);
    }

    // Runtime health watchdog: detect disconnected or stalled IMU within 500 ms
    if (now - last_event_ms_ > IMU_STALE_TIMEOUT_MS) {
        Serial.println("[IMU] Warning: BNO085 report stream stalled! Marking offline for recovery...");
        is_initialized_.store(false, std::memory_order_release);
        last_reconnect_attempt_ms_ = now;
        return false;
    }

    if (new_vector_received) {
        portENTER_CRITICAL(&imu_mux_);
        sample = current_sample_;
        portEXIT_CRITICAL(&imu_mux_);
        sample_count_.fetch_add(1, std::memory_order_relaxed);
        return true;
    }

    return false;
}

