#pragma once

#include <Arduino.h>
#include <atomic>
#include "config.h"
#include "types.h"

/**
 * @file power_manager.h
 * @brief Power latching, battery voltage monitoring, and automotive auto-shutdown.
 */
class PowerManager {
public:
    PowerManager();
    void begin();
    void update(bool ble_connected = false, uint16_t engine_rpm = 0);

    PowerState getState() const;
    float getBatteryVoltage() const;
    bool isEngineRunning() const;
    uint32_t getShutdownRemainingMs() const;
    bool isShutdownRequested() const;
    void forcePowerOff();
    void cancelShutdown();

private:
    std::atomic<PowerState> state_;
    std::atomic<float> battery_voltage_;
    std::atomic<bool> is_engine_running_;
    bool digital_sense_state_;
    bool was_engine_running_;
    std::atomic<uint32_t> countdown_start_ms_;
    uint32_t boot_idle_start_ms_;
    uint32_t last_adc_read_ms_;

    float readBatteryVoltageAdc();
};

