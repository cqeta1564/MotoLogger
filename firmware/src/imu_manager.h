#pragma once

#include <Arduino.h>
#include <SPI.h>
#include <Adafruit_BNO08x.h>
#include <atomic>
#include "config.h"
#include "types.h"

/**
 * @file imu_manager.h
 * @brief Manages CEVA/Hillcrest BNO085 9-DoF IMU via Dedicated HSPI, extracting
 *        100 Hz Game Rotation Vectors, Lean Angle (Roll), and G-forces.
 */
class ImuManager {
public:
    ImuManager();
    bool begin();
    bool update(ImuSample& sample);
    void tareZero();
    void setRollOffset(float offset_deg);
    float getRollOffset() const;
    void saveCalibrationToNvs();
    void loadCalibrationFromNvs();
    ImuSample getLatestSample();

    bool isReady() const { return is_initialized_.load(std::memory_order_acquire); }
    uint32_t getSampleCount() const { return sample_count_.load(std::memory_order_relaxed); }

private:
    SPIClass spi_imu_;
    bool spi_bus_initialized_;
    Adafruit_BNO08x bno_;
    sh2_SensorValue_t sensor_value_;
    std::atomic<bool> is_initialized_;
    std::atomic<uint32_t> sample_count_;

    // Uncalibrated raw orientation and zero-calibration offsets
    float raw_roll_deg_;
    float raw_pitch_deg_;
    float roll_offset_deg_;
    float pitch_offset_deg_;

    // Current cached values
    ImuSample current_sample_;
    mutable portMUX_TYPE imu_mux_;

    uint32_t last_reconnect_attempt_ms_;
    uint32_t last_event_ms_;

    static float normalizeAngle180(float angle_deg);
    static float clampPitch90(float pitch_deg);
    void quaternionToEuler(float qr, float qi, float qj, float qk, 
                           float& roll_deg, float& pitch_deg, float& yaw_deg);
    bool waitForIntLowMs(uint32_t timeout_ms) const;
    bool initSensorHardware();
    bool enableReports();
    bool tryReconnect();
};

