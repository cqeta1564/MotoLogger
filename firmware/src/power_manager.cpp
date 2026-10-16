#include "power_manager.h"

PowerManager::PowerManager()
    : state_(PowerState::BOOTING),
      battery_voltage_(12.6f),
      is_engine_running_(false),
      digital_sense_state_(false),
      was_engine_running_(false),
      countdown_start_ms_(0),
      boot_idle_start_ms_(0),
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
    analogSetPinAttenuation(PIN_SENSE_V_ANA, ADC_11db);

    // Give 3.3V rail 20 ms to stabilize
    delay(20);

    // Average 8 initial ADC samples to seed the IIR filter cleanly
    float v_sum = 0.0f;
    for (int i = 0; i < 8; i++) {
        v_sum += readBatteryVoltageAdc();
        delay(1);
    }
    float initial_v = v_sum / 8.0f;
    battery_voltage_.store(initial_v, std::memory_order_release);

    digital_sense_state_ = (digitalRead(PIN_SENSE_V_DIG) == HIGH);
    bool running_now = digital_sense_state_ || (initial_v >= V_BAT_RUNNING_VOLTS);
    is_engine_running_.store(running_now, std::memory_order_release);

    boot_idle_start_ms_ = millis();
    last_adc_read_ms_ = boot_idle_start_ms_;

    if (running_now) {
        state_.store(PowerState::RUNNING, std::memory_order_release);
        was_engine_running_ = true;
    } else {
        // Started without engine running (e.g. key on for calibration or USB bench debug)
        state_.store(PowerState::BOOTING, std::memory_order_release);
    }
}

float PowerManager::readBatteryVoltageAdc() {
    // ESP32-S3 analogReadMilliVolts utilizes internal factory calibration curve (eFuse)
    uint32_t raw_mv = analogReadMilliVolts(PIN_SENSE_V_ANA);
    float adc_volts = static_cast<float>(raw_mv) / 1000.0f;
    return adc_volts * V_BAT_DIVIDER_RATIO;
}

void PowerManager::update(bool ble_connected, uint16_t engine_rpm) {
    uint32_t now = millis();
    float v_bat = battery_voltage_.load(std::memory_order_relaxed);

    // Sample ADC at 10 Hz rate with IIR low-pass filter
    if (now - last_adc_read_ms_ >= 100) {
        last_adc_read_ms_ = now;
        float current_v = readBatteryVoltageAdc();
        v_bat = (v_bat * 0.85f) + (current_v * 0.15f);
        battery_voltage_.store(v_bat, std::memory_order_release);
    }

    digital_sense_state_ = (digitalRead(PIN_SENSE_V_DIG) == HIGH);

    // Engine is active if:
    // 1. Digital alternator sense pin is asserted, OR
    // 2. Battery voltage exceeds charging threshold (>= 13.0V), OR
    // 3. Live CAN bus reports running engine RPM (>= 400 RPM)
    bool engine_active = digital_sense_state_ ||
                         (v_bat >= V_BAT_RUNNING_VOLTS) ||
                         (engine_rpm >= 400);

    is_engine_running_.store(engine_active, std::memory_order_release);

    if (engine_active) {
        was_engine_running_ = true;
    }

    // Distinguish USB-only bench power (< 6.5V) from 12V motorcycle battery power
    bool on_battery_supply = (v_bat >= V_BAT_MIN_PRESENT_VOLTS);
    bool critical_low_battery = on_battery_supply && !engine_active && (v_bat < V_BAT_CUTOFF_VOLTS);
    bool usb_bench_mode = !on_battery_supply && bool(Serial);

    // Pure USB bench mode (no 12V battery attached): stay awake indefinitely
    if (usb_bench_mode) {
        if (state_.load(std::memory_order_acquire) == PowerState::COUNTDOWN_TO_SHUTDOWN) {
            cancelShutdown();
        }
        state_.store(PowerState::RUNNING, std::memory_order_release);
        return;
    }

    PowerState current_state = state_.load(std::memory_order_acquire);

    switch (current_state) {
        case PowerState::BOOTING:
            if (engine_active) {
                state_.store(PowerState::RUNNING, std::memory_order_release);
                countdown_start_ms_.store(0, std::memory_order_release);
            } else if (critical_low_battery) {
                // Protect deeply discharged motorcycle battery immediately
                countdown_start_ms_.store(now, std::memory_order_release);
                state_.store(PowerState::COUNTDOWN_TO_SHUTDOWN, std::memory_order_release);
            } else if (ble_connected || bool(Serial)) {
                // Rider is connected via BLE before engine start (calibrating tank or configuring CAN):
                // reset the 3-minute idle timer so calibration is never interrupted.
                boot_idle_start_ms_ = now;
            } else {
                // Key turned on without engine start or BLE connection:
                // Allow a 3-minute grace period before initiating power-saving shutdown.
                if (boot_idle_start_ms_ == 0) {
                    boot_idle_start_ms_ = now;
                } else if (now - boot_idle_start_ms_ >= 180000) {
                    countdown_start_ms_.store(now, std::memory_order_release);
                    state_.store(PowerState::COUNTDOWN_TO_SHUTDOWN, std::memory_order_release);
                }
            }
            break;

        case PowerState::RUNNING:
            if (!engine_active && (was_engine_running_ || critical_low_battery)) {
                // Ignition switched off after riding (or critical battery drop):
                // start 15-second auto-shutdown countdown (reported via BLE status_flags Bit 2).
                countdown_start_ms_.store(now, std::memory_order_release);
                state_.store(PowerState::COUNTDOWN_TO_SHUTDOWN, std::memory_order_release);
            }
            break;

        case PowerState::COUNTDOWN_TO_SHUTDOWN:
            if (engine_active) {
                // Engine restarted during the 15s grace period -> resume normal operation!
                countdown_start_ms_.store(0, std::memory_order_release);
                state_.store(PowerState::RUNNING, std::memory_order_release);
            } else if (now - countdown_start_ms_.load(std::memory_order_acquire) >= AUTO_SHUTDOWN_DELAY_MS) {
                // 15-second grace period expired -> trigger safe SD flush & 0 mA hardware power-off
                state_.store(PowerState::SHUTTING_DOWN, std::memory_order_release);
            }
            break;

        case PowerState::SHUTTING_DOWN:
            // Waiting for StorageManager to finalize, flush, and close session files
            break;
    }
}

void PowerManager::cancelShutdown() {
    countdown_start_ms_.store(0, std::memory_order_release);
    boot_idle_start_ms_ = millis();
    state_.store(was_engine_running_ ? PowerState::RUNNING : PowerState::BOOTING, std::memory_order_release);
}

PowerState PowerManager::getState() const {
    return state_.load(std::memory_order_acquire);
}

float PowerManager::getBatteryVoltage() const {
    return battery_voltage_.load(std::memory_order_acquire);
}

bool PowerManager::isEngineRunning() const {
    return is_engine_running_.load(std::memory_order_acquire);
}

uint32_t PowerManager::getShutdownRemainingMs() const {
    if (state_.load(std::memory_order_acquire) != PowerState::COUNTDOWN_TO_SHUTDOWN) return 0;
    uint32_t start = countdown_start_ms_.load(std::memory_order_acquire);
    uint32_t elapsed = millis() - start;
    if (elapsed >= AUTO_SHUTDOWN_DELAY_MS) return 0;
    return AUTO_SHUTDOWN_DELAY_MS - elapsed;
}

bool PowerManager::isShutdownRequested() const {
    return state_.load(std::memory_order_acquire) == PowerState::SHUTTING_DOWN;
}

void PowerManager::forcePowerOff() {
    // 1. Disable switched 3.3V rail (powers down BNO085 IMU and external sensors)
    digitalWrite(PIN_3V3_SWITCH, LOW);
    delay(10);
    // 2. Drop power latch: logger hardware completely powers down with 0 mA drain
    digitalWrite(PIN_FORCE_ON, LOW);
}

