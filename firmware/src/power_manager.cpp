#include "power_manager.h"

PowerManager::PowerManager()
    : state_(PowerState::BOOTING),
      battery_voltage_(12.6f),
      digital_sense_state_(false),
      countdown_start_ms_(0),
      last_adc_read_ms_(0) {}

void PowerManager::begin() {
    // 1. Immediately assert FORCE_ON to maintain power latch from 12V automotive supply
    pinMode(PIN_FORCE_ON, OUTPUT);
    digitalWrite(PIN_FORCE_ON, HIGH);

    // 2. Enable switched 3.3V rail to supply BNO085 IMU and external sensors
    pinMode(PIN_3V3_SWITCH, OUTPUT);
    digitalWrite(PIN_3V3_SWITCH, HIGH);

    // 3. Configure sensing inputs
    pinMode(PIN_SENSE_V_DIG, INPUT_PULLUP);
    pinMode(PIN_SENSE_V_ANA, INPUT);
    analogReadResolution(12);

    // Give 3.3V rail 20 ms to stabilize
    delay(20);

    battery_voltage_ = readBatteryVoltageAdc();
    digital_sense_state_ = (digitalRead(PIN_SENSE_V_DIG) == HIGH);

    if (digital_sense_state_ || battery_voltage_ >= V_BAT_RUNNING_VOLTS) {
        state_ = PowerState::RUNNING;
    } else {
        // Started without engine running (e.g. key on or USB debug)
        state_ = PowerState::BOOTING;
    }
}

float PowerManager::readBatteryVoltageAdc() {
    // ESP32-S3 analogReadMilliVolts utilizes internal factory calibration curve (eFuse)
    uint32_t raw_mv = analogReadMilliVolts(PIN_SENSE_V_ANA);
    float adc_volts = raw_mv / 1000.0f;
    return adc_volts * V_BAT_DIVIDER_RATIO;
}

void PowerManager::update() {
    uint32_t now = millis();

    // Sample ADC at 10 Hz rate
    if (now - last_adc_read_ms_ >= 100) {
        last_adc_read_ms_ = now;
        // Simple IIR low-pass filter for smooth battery reading
        float current_v = readBatteryVoltageAdc();
        battery_voltage_ = (battery_voltage_ * 0.85f) + (current_v * 0.15f);
    }

    digital_sense_state_ = (digitalRead(PIN_SENSE_V_DIG) == HIGH);
    bool engine_active = digital_sense_state_ || (battery_voltage_ >= V_BAT_RUNNING_VOLTS);

    switch (state_) {
        case PowerState::BOOTING:
            if (engine_active) {
                state_ = PowerState::RUNNING;
            } else {
                // If engine not started after 5 seconds from boot, start countdown
                if (countdown_start_ms_ == 0) {
                    countdown_start_ms_ = now;
                } else if (now - countdown_start_ms_ >= 5000) {
                    state_ = PowerState::COUNTDOWN_TO_SHUTDOWN;
                    countdown_start_ms_ = now;
                }
            }
            break;

        case PowerState::RUNNING:
            if (!engine_active) {
                // Engine shut off, transition to countdown
                state_ = PowerState::COUNTDOWN_TO_SHUTDOWN;
                countdown_start_ms_ = now;
            }
            break;

        case PowerState::COUNTDOWN_TO_SHUTDOWN:
            if (engine_active) {
                // Engine was restarted during countdown - resume normal running!
                state_ = PowerState::RUNNING;
                countdown_start_ms_ = 0;
            } else if (now - countdown_start_ms_ >= AUTO_SHUTDOWN_DELAY_MS) {
                // Grace period expired, trigger safe shutdown
                state_ = PowerState::SHUTTING_DOWN;
            }
            break;

        case PowerState::SHUTTING_DOWN:
            // Waiting for storage manager to finalize and close files
            break;
    }
}

PowerState PowerManager::getState() const {
    return state_;
}

float PowerManager::getBatteryVoltage() const {
    return battery_voltage_;
}

bool PowerManager::isEngineRunning() const {
    return digital_sense_state_ || (battery_voltage_ >= V_BAT_RUNNING_VOLTS);
}

uint32_t PowerManager::getShutdownRemainingMs() const {
    if (state_ != PowerState::COUNTDOWN_TO_SHUTDOWN) return 0;
    uint32_t elapsed = millis() - countdown_start_ms_;
    if (elapsed >= AUTO_SHUTDOWN_DELAY_MS) return 0;
    return AUTO_SHUTDOWN_DELAY_MS - elapsed;
}

bool PowerManager::isShutdownRequested() const {
    return state_ == PowerState::SHUTTING_DOWN;
}

void PowerManager::forcePowerOff() {
    // 1. Disable switched 3.3V rail
    digitalWrite(PIN_3V3_SWITCH, LOW);
    delay(10);
    // 2. Drop power latch: logger hardware completely turns off
    digitalWrite(PIN_FORCE_ON, LOW);
}
