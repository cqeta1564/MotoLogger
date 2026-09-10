#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_BNO08x.h>
#include "config.h"
#include "types.h"

/**
 * @file imu_manager.h
 * @brief Manages CEVA/Hillcrest BNO085 9-DoF IMU via I2C, extracting
 *        100 Hz Game Rotation Vectors, Lean Angle (Roll), and G-forces.
 */
class ImuManager {
public:
    ImuManager();
    bool begin();
    bool update(ImuSample& sample);
    void tareZero();
    void setRollOffset(float offset_deg);
    float getRollOffset() const { return roll_offset_deg_; }
    void saveCalibrationToNvs();
    void loadCalibrationFromNvs();
    ImuSample getLatestSample();

    bool isReady() const { return is_initialized_; }
    uint32_t getSampleCount() const { return sample_count_; }

private:
    Adafruit_BNO08x bno_;
    sh2_SensorValue_t sensor_value_;
    bool is_initialized_;
    uint32_t sample_count_;

    // Zero-calibration offsets
    float roll_offset_deg_;
    float pitch_offset_deg_;

    // Current cached values
    ImuSample current_sample_;
    portMUX_TYPE imu_mux_;

    void quaternionToEuler(float qr, float qi, float qj, float qk, 
                           float& roll_deg, float& pitch_deg, float& yaw_deg);
    bool enableReports();
};
