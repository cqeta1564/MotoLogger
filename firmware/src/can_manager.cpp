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
      rx_count_(0),
      tx_count_(0),
      error_count_(0),
      obd_mux_(portMUX_INITIALIZER_UNLOCKED),
      current_pid_index_(0),
      last_query_time_ms_(0) {
    memset(&obd_data_, 0, sizeof(obd_data_));
    obd_data_.gear = -1;
    memset(&custom_profile_, 0, sizeof(custom_profile_));
    custom_profile_.magic = 0x4D4F544F;
}

bool CanManager::begin(OperatingMode mode) {
    // 0. Load any custom motorcycle profile saved in NVS
    loadProfileFromNvs();
    if (custom_profile_.profile_active) {
        mode = OperatingMode::LISTEN_ONLY;
        Serial.println("[CAN] Active custom motorcycle profile loaded from NVS!");
    }

    mode_ = mode;

    // 1. Configure transceiver slope control / standby pin
    // Setting CAN_RS (GPIO38) to LOW places SN65HVD230 in High-Speed mode
    pinMode(PIN_CAN_RS, OUTPUT);
    digitalWrite(PIN_CAN_RS, LOW);

    // 2. Configure TWAI Driver
    twai_mode_t twai_mode = (mode_ == OperatingMode::LISTEN_ONLY) 
                            ? TWAI_MODE_LISTEN_ONLY 
                            : TWAI_MODE_NORMAL;

    twai_general_config_t g_config = TWAI_GENERAL_CONFIG_DEFAULT(
        PIN_CAN_TX, 
        PIN_CAN_RX, 
        twai_mode
    );
    g_config.rx_queue_len = CAN_RX_QUEUE_SIZE;
    g_config.alerts_enabled = TWAI_ALERT_BUS_ERROR | TWAI_ALERT_RECOVERY_IN_PROGRESS;

    twai_timing_config_t t_config = TWAI_TIMING_CONFIG_500KBITS();
    twai_filter_config_t f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    if (twai_driver_install(&g_config, &t_config, &f_config) != ESP_OK) {
        return false;
    }
    is_installed_ = true;

    if (twai_start() != ESP_OK) {
        return false;
    }
    is_running_ = true;

    return true;
}

void CanManager::stop() {
    if (is_running_) {
        twai_stop();
        is_running_ = false;
    }
    if (is_installed_) {
        twai_driver_uninstall();
        is_installed_ = false;
    }
    // Put transceiver in low power standby
    digitalWrite(PIN_CAN_RS, HIGH);
}

bool CanManager::receiveFrame(CanFrame& frame, uint32_t wait_ms) {
    if (!is_running_) return false;

    twai_message_t msg;
    esp_err_t res = twai_receive(&msg, pdMS_TO_TICKS(wait_ms));
    if (res != ESP_OK) {
        return false;
    }

    rx_count_++;

    frame.timestamp_us = esp_timer_get_time();
    frame.id = msg.identifier;
    frame.dlc = msg.data_length_code;
    frame.is_extended = msg.extd;
    frame.is_rtr = msg.rtr;
    memcpy(frame.data, msg.data, msg.data_length_code);

    // Real-Time Decoding: custom bike profile vs standard OBD-II response
    if (custom_profile_.profile_active) {
        decodeCustomFrame(msg);
    } else if (msg.identifier >= 0x7E8 && msg.identifier <= 0x7EF) {
        parseObdResponse(msg);
    }

    return true;
}

bool CanManager::transmitFrame(const CanFrame& frame, uint32_t timeout_ms) {
    if (!is_running_ || mode_ == OperatingMode::LISTEN_ONLY) return false;

    twai_message_t msg;
    msg.identifier = frame.id;
    msg.extd = frame.is_extended;
    msg.rtr = frame.is_rtr;
    msg.data_length_code = frame.dlc;
    memcpy(msg.data, frame.data, frame.dlc);

    esp_err_t res = twai_transmit(&msg, pdMS_TO_TICKS(timeout_ms));
    if (res == ESP_OK) {
        tx_count_++;
        return true;
    } else {
        error_count_++;
        return false;
    }
}

void CanManager::sendObdRequest(uint8_t pid) {
    CanFrame req;
    req.id = 0x7DF; // Standard 11-bit functional broadcast ID
    req.is_extended = false;
    req.is_rtr = false;
    req.dlc = 8;
    req.data[0] = 0x02; // Number of additional data bytes
    req.data[1] = 0x01; // Service 01 (Current Powertrain Diagnostic Data)
    req.data[2] = pid;
    req.data[3] = 0x55; // Padding
    req.data[4] = 0x55;
    req.data[5] = 0x55;
    req.data[6] = 0x55;
    req.data[7] = 0x55;

    transmitFrame(req, 10);
}

void CanManager::updateObdQueries() {
    if (custom_profile_.profile_active || mode_ != OperatingMode::ACTIVE_OBD || !is_running_) return;

    uint32_t now = millis();
    // Query each PID sequentially every 50 ms (20 Hz query cycle across 4 PIDs = ~5 Hz per PID)
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
    // Valid only when moving and clutch is fully engaged
    if (obd_data_.vehicle_speed_kmh < 10 || obd_data_.engine_rpm < 1500) {
        if (obd_data_.vehicle_speed_kmh == 0 && obd_data_.engine_rpm > 500) {
            obd_data_.gear = 0; // Neutral / stationary
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

ObdTelemetry CanManager::getTelemetry() {
    ObdTelemetry data;
    portENTER_CRITICAL(&obd_mux_);
    data = obd_data_;
    portEXIT_CRITICAL(&obd_mux_);
    return data;
}

// ==============================================================================
// Custom Motorcycle CAN Profile & NVS Persistence
// ==============================================================================
void CanManager::setSignalConfig(uint8_t signal_id, const CanSignalConfig& cfg) {
    portENTER_CRITICAL(&obd_mux_);
    switch (static_cast<CanSignalType>(signal_id)) {
        case CanSignalType::RPM:
            custom_profile_.rpm = cfg;
            break;
        case CanSignalType::SPEED:
            custom_profile_.speed = cfg;
            break;
        case CanSignalType::THROTTLE:
            custom_profile_.throttle = cfg;
            break;
        case CanSignalType::GEAR:
            custom_profile_.gear = cfg;
            break;
        case CanSignalType::COOLANT:
            custom_profile_.coolant = cfg;
            break;
        default:
            break;
    }
    custom_profile_.profile_active = 1;
    portEXIT_CRITICAL(&obd_mux_);

    saveProfileToNvs();
    Serial.printf("[CAN] Signal %u updated (ID: 0x%03X, Start: %u, Len: %u, BigEnd: %u, Mult: %.4f, Off: %.1f)\n",
                  signal_id, cfg.can_id, cfg.start_byte, cfg.length_bytes, cfg.is_big_endian, cfg.multiplier, cfg.offset);
}

void CanManager::setProfileActive(bool active) {
    portENTER_CRITICAL(&obd_mux_);
    custom_profile_.profile_active = active ? 1 : 0;
    portEXIT_CRITICAL(&obd_mux_);
    saveProfileToNvs();
    Serial.printf("[CAN] Profile active mode set to: %s\n", active ? "CUSTOM_CAN" : "OBD_STANDARD");
}

void CanManager::saveProfileToNvs() {
    Preferences prefs;
    if (prefs.begin("motologger", false)) {
        prefs.putBytes("can_prof", &custom_profile_, sizeof(custom_profile_));
        prefs.end();
        Serial.println("[CAN] Profile saved to NVS successfully.");
    } else {
        Serial.println("[CAN] Failed to open NVS for writing profile!");
    }
}

void CanManager::loadProfileFromNvs() {
    Preferences prefs;
    if (prefs.begin("motologger", true)) {
        size_t read_bytes = prefs.getBytes("can_prof", &custom_profile_, sizeof(custom_profile_));
        prefs.end();
        if (read_bytes == sizeof(custom_profile_) && custom_profile_.magic == 0x4D4F544F) {
            Serial.printf("[CAN] Loaded profile from NVS (active: %u)\n", custom_profile_.profile_active);
        } else {
            memset(&custom_profile_, 0, sizeof(custom_profile_));
            custom_profile_.magic = 0x4D4F544F;
        }
    }
}

float CanManager::decodeSignalValue(const CanSignalConfig& cfg, const uint8_t* payload, uint8_t dlc) {
    if (cfg.start_byte + cfg.length_bytes > dlc) return 0.0f;

    uint32_t raw = 0;
    if (cfg.length_bytes == 1) {
        raw = payload[cfg.start_byte];
    } else if (cfg.length_bytes == 2) {
        if (cfg.is_big_endian) {
            raw = (static_cast<uint32_t>(payload[cfg.start_byte]) << 8) | payload[cfg.start_byte + 1];
        } else {
            raw = payload[cfg.start_byte] | (static_cast<uint32_t>(payload[cfg.start_byte + 1]) << 8);
        }
    }

    return (static_cast<float>(raw) * cfg.multiplier) + cfg.offset;
}

void CanManager::decodeCustomFrame(const twai_message_t& msg) {
    bool updated = false;

    portENTER_CRITICAL(&obd_mux_);
    // 1. Engine RPM
    if (custom_profile_.rpm.is_active && msg.identifier == custom_profile_.rpm.can_id) {
        float val = decodeSignalValue(custom_profile_.rpm, msg.data, msg.data_length_code);
        obd_data_.engine_rpm = static_cast<uint16_t>(fmaxf(0.0f, fminf(val, 25000.0f)));
        updated = true;
    }
    // 2. Vehicle Speed
    if (custom_profile_.speed.is_active && msg.identifier == custom_profile_.speed.can_id) {
        float val = decodeSignalValue(custom_profile_.speed, msg.data, msg.data_length_code);
        obd_data_.vehicle_speed_kmh = static_cast<uint8_t>(fmaxf(0.0f, fminf(val, 255.0f)));
        updated = true;
    }
    // 3. Throttle Position
    if (custom_profile_.throttle.is_active && msg.identifier == custom_profile_.throttle.can_id) {
        float val = decodeSignalValue(custom_profile_.throttle, msg.data, msg.data_length_code);
        obd_data_.throttle_pos_pct = fmaxf(0.0f, fminf(val, 100.0f));
        updated = true;
    }
    // 4. Gear
    if (custom_profile_.gear.is_active && msg.identifier == custom_profile_.gear.can_id) {
        float val = decodeSignalValue(custom_profile_.gear, msg.data, msg.data_length_code);
        obd_data_.gear = static_cast<int8_t>(val);
        updated = true;
    }
    // 5. Coolant Temp
    if (custom_profile_.coolant.is_active && msg.identifier == custom_profile_.coolant.can_id) {
        float val = decodeSignalValue(custom_profile_.coolant, msg.data, msg.data_length_code);
        obd_data_.coolant_temp_c = static_cast<int16_t>(val);
        updated = true;
    }

    if (updated) {
        obd_data_.last_update_ms = millis();
        obd_data_.data_valid = true;
    }
    portEXIT_CRITICAL(&obd_mux_);
}

