#include "can_manager.h"
#include <Preferences.h>
#include <math.h>

// Standard OBD-II PIDs to query in Active Mode
static const uint8_t OBD_PID_LIST[] = {
    0x0C, // Engine RPM (2 bytes)
    0x0D, // Vehicle Speed (1 byte)
    0x11, // Throttle Position (1 byte)
    0x05  // Engine Coolant Temperature (1 byte)
};
static constexpr size_t OBD_PID_COUNT = sizeof(OBD_PID_LIST) / sizeof(OBD_PID_LIST[0]);

CanManager::CanManager()
    : mode_(OperatingMode::LISTEN_ONLY),
      is_installed_(false),
      is_running_(false),
      is_recovering_(false),
      mode_change_pending_(false),
      pending_mode_(OperatingMode::LISTEN_ONLY),
      rx_count_(0),
      tx_count_(0),
      error_count_(0),
      bus_off_count_(0),
      last_bus_off_time_ms_(0),
      obd_mux_(portMUX_INITIALIZER_UNLOCKED),
      current_pid_index_(0),
      last_query_time_ms_(0) {
    memset(&obd_data_, 0, sizeof(obd_data_));
    obd_data_.gear = -1;
    memset(&custom_profile_, 0, sizeof(custom_profile_));
    custom_profile_.magic = 0x4D4F544F;
}

bool CanManager::installAndStartTwai(OperatingMode mode) {
    if (is_running_.load(std::memory_order_acquire)) {
        twai_stop();
        is_running_.store(false, std::memory_order_release);
    }
    if (is_installed_.load(std::memory_order_acquire)) {
        twai_driver_uninstall();
        is_installed_.store(false, std::memory_order_release);
    }

    mode_ = mode;
    is_recovering_.store(false, std::memory_order_release);

    twai_mode_t twai_mode = (mode_ == OperatingMode::LISTEN_ONLY)
                            ? TWAI_MODE_LISTEN_ONLY
                            : TWAI_MODE_NORMAL;

    twai_general_config_t g_config = TWAI_GENERAL_CONFIG_DEFAULT(
        PIN_CAN_TX,
        PIN_CAN_RX,
        twai_mode
    );
    g_config.rx_queue_len = CAN_RX_QUEUE_SIZE;
    g_config.tx_queue_len = 16;
    g_config.alerts_enabled = TWAI_ALERT_BUS_ERROR |
                              TWAI_ALERT_BUS_OFF |
                              TWAI_ALERT_BUS_RECOVERED |
                              TWAI_ALERT_RECOVERY_IN_PROGRESS |
                              TWAI_ALERT_RX_QUEUE_FULL;

    twai_timing_config_t t_config = TWAI_TIMING_CONFIG_500KBITS();
    twai_filter_config_t f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    if (twai_driver_install(&g_config, &t_config, &f_config) != ESP_OK) {
        return false;
    }
    is_installed_.store(true, std::memory_order_release);

    if (twai_start() != ESP_OK) {
        twai_driver_uninstall();
        is_installed_.store(false, std::memory_order_release);
        return false;
    }
    is_running_.store(true, std::memory_order_release);
    return true;
}

bool CanManager::begin(OperatingMode mode) {
    // 0. Load any custom motorcycle profile saved in NVS
    loadProfileFromNvs();
    if (custom_profile_.profile_active) {
        mode = OperatingMode::LISTEN_ONLY;
        Serial.println("[CAN] Active custom motorcycle profile loaded from NVS (Listen-Only).");
    }

    // 1. Configure transceiver slope control / standby pin
    // Setting CAN_RS (GPIO38) to LOW places SN65HVD230 in High-Speed mode
    pinMode(PIN_CAN_RS, OUTPUT);
    digitalWrite(PIN_CAN_RS, LOW);

    // 2. Install and start TWAI driver
    return installAndStartTwai(mode);
}

bool CanManager::reconfigureMode(OperatingMode new_mode) {
    pending_mode_ = new_mode;
    mode_change_pending_.store(true, std::memory_order_release);
    return true;
}

void CanManager::stop() {
    if (is_running_.load(std::memory_order_acquire)) {
        twai_stop();
        is_running_.store(false, std::memory_order_release);
    }
    if (is_installed_.load(std::memory_order_acquire)) {
        twai_driver_uninstall();
        is_installed_.store(false, std::memory_order_release);
    }
    // Put SN65HVD230 transceiver in low-power standby mode
    digitalWrite(PIN_CAN_RS, HIGH);
}

void CanManager::handleBusRecovery() {
    // Process any pending mode switch requested from BLE task safely on Task_CAN
    if (mode_change_pending_.exchange(false, std::memory_order_acq_rel)) {
        OperatingMode target = pending_mode_;
        if (target != mode_ || !is_running_.load(std::memory_order_acquire)) {
            if (installAndStartTwai(target)) {
                Serial.printf("[CAN] Reconfigured TWAI mode to %s\n",
                              (target == OperatingMode::LISTEN_ONLY) ? "LISTEN_ONLY" : "ACTIVE_OBD");
            }
        }
    }

    if (!is_installed_.load(std::memory_order_acquire)) return;

    uint32_t alerts = 0;
    esp_err_t err = twai_read_alerts(&alerts, 0);
    if (err == ESP_OK && alerts != 0) {
        if (alerts & TWAI_ALERT_BUS_OFF) {
            uint32_t count = bus_off_count_.fetch_add(1, std::memory_order_relaxed) + 1;
            is_recovering_.store(true, std::memory_order_release);
            last_bus_off_time_ms_ = millis();
            Serial.printf("[CAN] TWAI Bus-Off detected (count: %lu)! Initiating auto-recovery...\n",
                          static_cast<unsigned long>(count));
            twai_initiate_recovery();
        }
        if (alerts & TWAI_ALERT_BUS_RECOVERED) {
            is_recovering_.store(false, std::memory_order_release);
            Serial.println("[CAN] TWAI Bus recovery complete! Restarting CAN driver...");
            if (twai_start() == ESP_OK) {
                is_running_.store(true, std::memory_order_release);
                Serial.println("[CAN] TWAI driver restarted and active.");
            } else {
                Serial.println("[CAN] ERROR: Failed to restart TWAI after recovery!");
            }
        }
        if (alerts & TWAI_ALERT_BUS_ERROR) {
            error_count_.fetch_add(1, std::memory_order_relaxed);
        }
        if (alerts & TWAI_ALERT_RX_QUEUE_FULL) {
            error_count_.fetch_add(1, std::memory_order_relaxed);
        }
    } else {
        // Fallback status check in case alert bit was missed or driver entered stopped/bus-off
        twai_status_info_t status;
        if (twai_get_status_info(&status) == ESP_OK) {
            if (status.state == TWAI_STATE_BUS_OFF && !is_recovering_.load(std::memory_order_acquire)) {
                bus_off_count_.fetch_add(1, std::memory_order_relaxed);
                is_recovering_.store(true, std::memory_order_release);
                last_bus_off_time_ms_ = millis();
                Serial.println("[CAN] TWAI state is BUS_OFF. Initiating recovery...");
                twai_initiate_recovery();
            } else if (status.state == TWAI_STATE_STOPPED && is_recovering_.load(std::memory_order_acquire)) {
                is_recovering_.store(false, std::memory_order_release);
                Serial.println("[CAN] TWAI stopped after recovery. Restarting driver...");
                if (twai_start() == ESP_OK) {
                    is_running_.store(true, std::memory_order_release);
                }
            }
        }
    }
}

bool CanManager::receiveFrame(CanFrame& frame, uint32_t wait_ms) {
    handleBusRecovery();
    if (!is_running_.load(std::memory_order_acquire) || is_recovering_.load(std::memory_order_acquire)) {
        if (wait_ms > 0) {
            vTaskDelay(pdMS_TO_TICKS(wait_ms));
        }
        return false;
    }

    twai_message_t msg = {};
    esp_err_t res = twai_receive(&msg, pdMS_TO_TICKS(wait_ms));
    if (res != ESP_OK) {
        return false;
    }

    rx_count_.fetch_add(1, std::memory_order_relaxed);

    uint8_t safe_dlc = (msg.data_length_code > 8) ? 8 : msg.data_length_code;
    frame.timestamp_us = esp_timer_get_time();
    frame.id = msg.identifier;
    frame.dlc = safe_dlc;
    frame.is_extended = (msg.extd != 0);
    frame.is_rtr = (msg.rtr != 0);
    memset(frame.data, 0, sizeof(frame.data));
    if (!frame.is_rtr && safe_dlc > 0) {
        memcpy(frame.data, msg.data, safe_dlc);
    }

    // Real-Time Decoding (skip Remote Transmission Request frames which carry no payload)
    if (!frame.is_rtr) {
        if (isCustomProfileActive()) {
            decodeCustomFrame(msg);
        } else if (msg.identifier >= 0x7E8 && msg.identifier <= 0x7EF) {
            parseObdResponse(msg);
        }
    }

    return true;
}

bool CanManager::transmitFrame(const CanFrame& frame, uint32_t timeout_ms, bool single_shot) {
    if (!is_running_.load(std::memory_order_acquire) ||
        is_recovering_.load(std::memory_order_acquire) ||
        mode_ == OperatingMode::LISTEN_ONLY) {
        return false;
    }

    twai_message_t msg = {};
    uint8_t safe_dlc = (frame.dlc > 8) ? 8 : frame.dlc;
    msg.identifier = frame.id;
    msg.extd = frame.is_extended ? 1 : 0;
    msg.rtr = frame.is_rtr ? 1 : 0;
    msg.ss = single_shot ? 1 : 0; // Single-shot prevents infinite TX retries when bus is disconnected
    msg.data_length_code = safe_dlc;
    if (!frame.is_rtr && safe_dlc > 0) {
        memcpy(msg.data, frame.data, safe_dlc);
    }

    esp_err_t res = twai_transmit(&msg, pdMS_TO_TICKS(timeout_ms));
    if (res == ESP_OK) {
        tx_count_.fetch_add(1, std::memory_order_relaxed);
        return true;
    } else {
        error_count_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
}

void CanManager::sendObdRequest(uint8_t pid) {
    CanFrame req = {};
    req.id = 0x7DF; // Standard 11-bit functional broadcast ID
    req.is_extended = false;
    req.is_rtr = false;
    req.dlc = 8;
    req.data[0] = 0x02; // Number of additional data bytes
    req.data[1] = 0x01; // Service 01 (Current Powertrain Diagnostic Data)
    req.data[2] = pid;
    req.data[3] = 0x55; // ISO 15765-4 padding
    req.data[4] = 0x55;
    req.data[5] = 0x55;
    req.data[6] = 0x55;
    req.data[7] = 0x55;

    transmitFrame(req, 5, true);
}

void CanManager::updateObdQueries() {
    if (isCustomProfileActive() ||
        mode_ != OperatingMode::ACTIVE_OBD ||
        !is_running_.load(std::memory_order_acquire) ||
        is_recovering_.load(std::memory_order_acquire)) {
        return;
    }

    uint32_t now = millis();
    // Query each PID sequentially every 50 ms (20 Hz query cycle across 4 PIDs = 5 Hz per PID)
    if (now - last_query_time_ms_ >= 50) {
        last_query_time_ms_ = now;
        sendObdRequest(OBD_PID_LIST[current_pid_index_]);
        current_pid_index_ = (current_pid_index_ + 1) % OBD_PID_COUNT;
    }
}

void CanManager::parseObdResponse(const twai_message_t& msg) {
    // Standard ISO 15765-4 single frame response:
    // data[0] = length
    // data[1] = 0x41 (Service 01 response)
    // data[2] = PID
    if (msg.data_length_code < 3 || msg.data[1] != 0x41) return;

    uint8_t pid = msg.data[2];

    portENTER_CRITICAL(&obd_mux_);
    obd_data_.last_update_ms = millis();
    obd_data_.data_valid = true;

    switch (pid) {
        case 0x0C: // Engine RPM: ((A * 256) + B) / 4
            if (msg.data_length_code >= 5) {
                obd_data_.engine_rpm = ((static_cast<uint16_t>(msg.data[3]) << 8) | msg.data[4]) / 4;
            }
            break;

        case 0x0D: // Vehicle Speed: A (km/h)
            if (msg.data_length_code >= 4) {
                obd_data_.vehicle_speed_kmh = msg.data[3];
            }
            break;

        case 0x11: // Throttle Position: (A * 100) / 255 (%)
            if (msg.data_length_code >= 4) {
                obd_data_.throttle_pos_pct = (msg.data[3] * 100.0f) / 255.0f;
            }
            break;

        case 0x05: // Coolant Temp: A - 40 (deg C)
            if (msg.data_length_code >= 4) {
                obd_data_.coolant_temp_c = static_cast<int16_t>(msg.data[3]) - 40;
            }
            break;

        default:
            break;
    }

    calculateGear();
    portEXIT_CRITICAL(&obd_mux_);
}

void CanManager::calculateGear() {
    // Automatic gear estimation based on RPM / Speed ratio (RPM per km/h)
    // Valid only when moving and clutch is engaged
    if (obd_data_.vehicle_speed_kmh < 10 || obd_data_.engine_rpm < 1500) {
        if (obd_data_.vehicle_speed_kmh == 0 && obd_data_.engine_rpm > 500) {
            obd_data_.gear = 0; // Neutral / stationary
        } else if (obd_data_.engine_rpm < 400) {
            obd_data_.gear = -1; // Engine off / unknown
        }
        return;
    }

    float ratio = static_cast<float>(obd_data_.engine_rpm) / static_cast<float>(obd_data_.vehicle_speed_kmh);

    // Typical motorcycle transmission bands (adjustable per bike gearing)
    if (ratio > 110.0f) {
        obd_data_.gear = 1;
    } else if (ratio > 85.0f) {
        obd_data_.gear = 2;
    } else if (ratio > 68.0f) {
        obd_data_.gear = 3;
    } else if (ratio > 56.0f) {
        obd_data_.gear = 4;
    } else if (ratio > 48.0f) {
        obd_data_.gear = 5;
    } else {
        obd_data_.gear = 6;
    }
}

void CanManager::checkTelemetryTimeoutLocked(uint32_t now_ms) {
    // If ECU stops transmitting (ignition turned off), clear stale RPM/speed
    // after CAN_TELEMETRY_TIMEOUT_MS (1.5 s) so PowerManager can trigger auto-shutdown!
    if (obd_data_.data_valid && (now_ms - obd_data_.last_update_ms > CAN_TELEMETRY_TIMEOUT_MS)) {
        obd_data_.engine_rpm = 0;
        obd_data_.vehicle_speed_kmh = 0;
        obd_data_.throttle_pos_pct = 0.0f;
        obd_data_.gear = -1;
        obd_data_.data_valid = false;
    }
}

ObdTelemetry CanManager::getTelemetry() {
    uint32_t now = millis();
    ObdTelemetry data;
    portENTER_CRITICAL(&obd_mux_);
    checkTelemetryTimeoutLocked(now);
    data = obd_data_;
    portEXIT_CRITICAL(&obd_mux_);
    return data;
}

bool CanManager::isCustomProfileActive() const {
    bool active;
    portENTER_CRITICAL(&obd_mux_);
    active = (custom_profile_.profile_active != 0);
    portEXIT_CRITICAL(&obd_mux_);
    return active;
}

// ==============================================================================
// Custom Motorcycle CAN Profile & NVS Persistence
// ==============================================================================
void CanManager::setSignalConfig(uint8_t signal_id, const CanSignalConfig& cfg) {
    CanSignalConfig sanitized = cfg;
    if (sanitized.start_byte > 7) sanitized.start_byte = 7;
    if (sanitized.length_bytes == 0 || sanitized.length_bytes > 4) {
        sanitized.is_active = 0;
    }
    if (!isfinite(sanitized.multiplier)) sanitized.multiplier = 1.0f;
    if (!isfinite(sanitized.offset)) sanitized.offset = 0.0f;

    portENTER_CRITICAL(&obd_mux_);
    switch (static_cast<CanSignalType>(signal_id)) {
        case CanSignalType::RPM:
            custom_profile_.rpm = sanitized;
            break;
        case CanSignalType::SPEED:
            custom_profile_.speed = sanitized;
            break;
        case CanSignalType::THROTTLE:
            custom_profile_.throttle = sanitized;
            break;
        case CanSignalType::GEAR:
            custom_profile_.gear = sanitized;
            break;
        case CanSignalType::COOLANT:
            custom_profile_.coolant = sanitized;
            break;
        default:
            break;
    }
    custom_profile_.profile_active = 1;
    portEXIT_CRITICAL(&obd_mux_);

    saveProfileToNvs();
    reconfigureMode(OperatingMode::LISTEN_ONLY);

    Serial.printf("[CAN] Signal %u updated (ID: 0x%03lX, Start: %u, Len: %u, BigEnd: %u, Mult: %.4f, Off: %.1f)\n",
                  signal_id, static_cast<unsigned long>(sanitized.can_id), sanitized.start_byte,
                  sanitized.length_bytes, sanitized.is_big_endian, sanitized.multiplier, sanitized.offset);
}

void CanManager::setProfileActive(bool active) {
    portENTER_CRITICAL(&obd_mux_);
    custom_profile_.profile_active = active ? 1 : 0;
    if (!active) {
        // Clear custom signal active flags when returning to Standard OBD-II mode
        custom_profile_.rpm.is_active = 0;
        custom_profile_.speed.is_active = 0;
        custom_profile_.throttle.is_active = 0;
        custom_profile_.gear.is_active = 0;
        custom_profile_.coolant.is_active = 0;
    }
    portEXIT_CRITICAL(&obd_mux_);

    saveProfileToNvs();
    reconfigureMode(active ? OperatingMode::LISTEN_ONLY : OperatingMode::ACTIVE_OBD);
    Serial.printf("[CAN] Profile active mode set to: %s\n", active ? "CUSTOM_CAN" : "OBD_STANDARD");
}

void CanManager::saveProfileToNvs() {
    EspBikeCanProfile snapshot;
    portENTER_CRITICAL(&obd_mux_);
    snapshot = custom_profile_;
    portEXIT_CRITICAL(&obd_mux_);

    Preferences prefs;
    if (prefs.begin("motologger", false)) {
        prefs.putBytes("can_prof", &snapshot, sizeof(snapshot));
        prefs.end();
        Serial.println("[CAN] Profile saved to NVS successfully.");
    } else {
        Serial.println("[CAN] Failed to open NVS for writing profile!");
    }
}

void CanManager::loadProfileFromNvs() {
    Preferences prefs;
    if (prefs.begin("motologger", true)) {
        EspBikeCanProfile loaded = {};
        size_t read_bytes = prefs.getBytes("can_prof", &loaded, sizeof(loaded));
        prefs.end();

        portENTER_CRITICAL(&obd_mux_);
        if (read_bytes == sizeof(loaded) && loaded.magic == 0x4D4F544F) {
            custom_profile_ = loaded;
            portEXIT_CRITICAL(&obd_mux_);
            Serial.printf("[CAN] Loaded profile from NVS (active: %u)\n", loaded.profile_active);
        } else {
            memset(&custom_profile_, 0, sizeof(custom_profile_));
            custom_profile_.magic = 0x4D4F544F;
            portEXIT_CRITICAL(&obd_mux_);
        }
    }
}

float CanManager::decodeSignalValue(const CanSignalConfig& cfg, const uint8_t* payload, uint8_t dlc) {
    if (cfg.length_bytes == 0 || cfg.length_bytes > 4 || cfg.start_byte + cfg.length_bytes > dlc) {
        return 0.0f;
    }

    uint32_t raw = 0;
    if (cfg.is_big_endian) {
        for (uint8_t i = 0; i < cfg.length_bytes; i++) {
            raw = (raw << 8) | payload[cfg.start_byte + i];
        }
    } else {
        for (uint8_t i = 0; i < cfg.length_bytes; i++) {
            raw |= (static_cast<uint32_t>(payload[cfg.start_byte + i]) << (8 * i));
        }
    }

    float result = (static_cast<float>(raw) * cfg.multiplier) + cfg.offset;
    return isfinite(result) ? result : 0.0f;
}

void CanManager::decodeCustomFrame(const twai_message_t& msg) {
    bool updated = false;
    bool rpm_or_speed_updated = false;
    uint8_t safe_dlc = (msg.data_length_code > 8) ? 8 : msg.data_length_code;

    portENTER_CRITICAL(&obd_mux_);
    // 1. Engine RPM
    if (custom_profile_.rpm.is_active && msg.identifier == custom_profile_.rpm.can_id) {
        float val = decodeSignalValue(custom_profile_.rpm, msg.data, safe_dlc);
        obd_data_.engine_rpm = static_cast<uint16_t>(lroundf(fmaxf(0.0f, fminf(val, 25000.0f))));
        updated = true;
        rpm_or_speed_updated = true;
    }
    // 2. Vehicle Speed
    if (custom_profile_.speed.is_active && msg.identifier == custom_profile_.speed.can_id) {
        float val = decodeSignalValue(custom_profile_.speed, msg.data, safe_dlc);
        obd_data_.vehicle_speed_kmh = static_cast<uint8_t>(lroundf(fmaxf(0.0f, fminf(val, 255.0f))));
        updated = true;
        rpm_or_speed_updated = true;
    }
    // 3. Throttle Position
    if (custom_profile_.throttle.is_active && msg.identifier == custom_profile_.throttle.can_id) {
        float val = decodeSignalValue(custom_profile_.throttle, msg.data, safe_dlc);
        obd_data_.throttle_pos_pct = fmaxf(0.0f, fminf(val, 100.0f));
        updated = true;
    }
    // 4. Gear
    if (custom_profile_.gear.is_active && msg.identifier == custom_profile_.gear.can_id) {
        float val = decodeSignalValue(custom_profile_.gear, msg.data, safe_dlc);
        int32_t gear_i = lroundf(fmaxf(-1.0f, fminf(val, 8.0f)));
        obd_data_.gear = static_cast<int8_t>(gear_i);
        updated = true;
    } else if (rpm_or_speed_updated && !custom_profile_.gear.is_active) {
        // Fallback: estimate gear from RPM / Speed ratio when no dedicated CAN gear signal is mapped
        calculateGear();
    }
    // 5. Coolant Temp
    if (custom_profile_.coolant.is_active && msg.identifier == custom_profile_.coolant.can_id) {
        float val = decodeSignalValue(custom_profile_.coolant, msg.data, safe_dlc);
        int32_t temp_i = lroundf(fmaxf(-40.0f, fminf(val, 200.0f)));
        obd_data_.coolant_temp_c = static_cast<int16_t>(temp_i);
        updated = true;
    }

    if (updated) {
        obd_data_.last_update_ms = millis();
        obd_data_.data_valid = true;
    }
    portEXIT_CRITICAL(&obd_mux_);
}

