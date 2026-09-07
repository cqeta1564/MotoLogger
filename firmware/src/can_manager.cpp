#include "can_manager.h"

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
}

bool CanManager::begin(OperatingMode mode) {
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

    // Parse OBD-II response if ID matches standard ECU diagnostic range (0x7E8 - 0x7EF)
    if (msg.identifier >= 0x7E8 && msg.identifier <= 0x7EF) {
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
    if (mode_ != OperatingMode::ACTIVE_OBD || !is_running_) return;

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
