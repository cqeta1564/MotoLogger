#pragma once

#include <Arduino.h>
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
    void update();

    PowerState getState() const;
    float getBatteryVoltage() const;
    bool isEngineRunning() const;
    uint32_t getShutdownRemainingMs() const;
    bool isShutdownRequested() const;
    void forcePowerOff();

private:
    PowerState state_;
    float battery_voltage_;
    bool digital_sense_state_;
    uint32_t countdown_start_ms_;
    uint32_t last_adc_read_ms_;

    float readBatteryVoltageAdc();
};
