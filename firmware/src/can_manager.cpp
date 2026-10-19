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
      diag_mode_active_(false),
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
      dtc_count_(0),
      isotp_pending_service_(0),
      obd_mux_(portMUX_INITIALIZER_UNLOCKED),
      current_pid_index_(0),
      last_query_time_ms_(0),
      dtc_scan_requested_(false),
      dtc_clear_requested_(false),
      dtc_clear_acknowledged_(false) {
    memset(&obd_data_, 0, sizeof(obd_data_));
    obd_data_.gear = -1;
    memset(dtc_list_, 0, sizeof(dtc_list_));
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

    twai_timing_config_t t_config;
    uint16_t baud = custom_profile_.baudrate_kbps;
    if (baud == 250) {
        t_config = TWAI_TIMING_CONFIG_250KBITS();
    } else if (baud == 1000) {
        t_config = TWAI_TIMING_CONFIG_1MBITS();
    } else {
        t_config = TWAI_TIMING_CONFIG_500KBITS();
    }
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
    (void)mode;
    // 0. Load any custom motorcycle profile saved in NVS
    loadProfileFromNvs();

    // Always boot strictly in passive LISTEN_ONLY mode (zero CAN bus transmission).
    // Active transmission is only enabled when the user explicitly enters Diagnostic Mode.
    diag_mode_active_.store(false, std::memory_order_release);

    // 1. Configure transceiver slope control / standby pin
    // Setting CAN_RS (GPIO38) to LOW places SN65HVD230 in High-Speed mode
    pinMode(PIN_CAN_RS, OUTPUT);
    digitalWrite(PIN_CAN_RS, LOW);

    // 2. Install and start TWAI driver in LISTEN_ONLY mode
    return installAndStartTwai(OperatingMode::LISTEN_ONLY);
}

bool CanManager::reconfigureMode(OperatingMode new_mode) {
    pending_mode_ = new_mode;
    mode_change_pending_.store(true, std::memory_order_release);
    return true;
}

void CanManager::setDiagnosticMode(bool enable) {
    diag_mode_active_.store(enable, std::memory_order_release);
    reconfigureMode(enable ? OperatingMode::ACTIVE_OBD : OperatingMode::LISTEN_ONLY);
    Serial.printf("[CAN] Diagnostic Mode %s (%s)\n",
                  enable ? "ENABLED" : "DISABLED",
                  enable ? "TWAI_MODE_NORMAL / Active OBD-II TX" : "TWAI_MODE_LISTEN_ONLY / Passive RX");
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
        }
        if (msg.identifier >= 0x7E8 && msg.identifier <= 0x7EF) {
            parseObdResponse(msg);
        }

        // Automotive Safety Interlock: Automatically exit active diagnostic TX if vehicle moves (> 5 km/h)
        if (diag_mode_active_.load(std::memory_order_acquire)) {
            uint8_t current_speed = 0;
            portENTER_CRITICAL(&obd_mux_);
            current_speed = obd_data_.vehicle_speed_kmh;
            portEXIT_CRITICAL(&obd_mux_);
            if (current_speed > 5) {
                Serial.printf("[CAN] Safety Interlock: Speed %u km/h > 5 km/h -> Disengaging Diagnostic TX Mode!\n",
                              static_cast<unsigned int>(current_speed));
                setDiagnosticMode(false);
            }
        }
    }

    return true;
}

bool CanManager::transmitFrame(const CanFrame& frame, uint32_t timeout_ms, bool single_shot) {
    // Strictly block any CAN transmission unless explicitly in Diagnostic Mode (ACTIVE_OBD)
    if (!is_running_.load(std::memory_order_acquire) ||
        is_recovering_.load(std::memory_order_acquire) ||
        !diag_mode_active_.load(std::memory_order_acquire) ||
        mode_ != OperatingMode::ACTIVE_OBD) {
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

void CanManager::sendObdServiceRequest(uint8_t service_id) {
    CanFrame req = {};
    req.id = 0x7DF;
    req.is_extended = false;
    req.is_rtr = false;
    req.dlc = 8;
    req.data[0] = 0x01; // 1 byte service request (0x03, 0x04, or 0x07)
    req.data[1] = service_id;
    req.data[2] = 0x55;
    req.data[3] = 0x55;
    req.data[4] = 0x55;
    req.data[5] = 0x55;
    req.data[6] = 0x55;
    req.data[7] = 0x55;

    transmitFrame(req, 10, true);
}

void CanManager::sendIsoTpFlowControl(uint32_t response_can_id) {
    if (response_can_id < 0x7E8 || response_can_id > 0x7EF) return;
    CanFrame fc = {};
    fc.id = response_can_id - 8; // Physical ECU request ID (0x7E0..0x7E7)
    fc.is_extended = false;
    fc.is_rtr = false;
    fc.dlc = 8;
    fc.data[0] = 0x30; // Flow Control: Continue To Send (CTS)
    fc.data[1] = 0x00; // Block Size = 0 (send all remaining frames)
    fc.data[2] = 0x05; // Separation Time (STmin) = 5 ms
    fc.data[3] = 0x55;
    fc.data[4] = 0x55;
    fc.data[5] = 0x55;
    fc.data[6] = 0x55;
    fc.data[7] = 0x55;

    transmitFrame(fc, 5, true);
}

void CanManager::requestDtcScan() {
    portENTER_CRITICAL(&obd_mux_);
    dtc_count_ = 0;
    isotp_pending_service_ = 0;
    memset(dtc_list_, 0, sizeof(dtc_list_));
    portEXIT_CRITICAL(&obd_mux_);
    dtc_scan_requested_.store(true, std::memory_order_release);
}

bool CanManager::requestClearDtc() {
    portENTER_CRITICAL(&obd_mux_);
    dtc_count_ = 0;
    isotp_pending_service_ = 0;
    memset(dtc_list_, 0, sizeof(dtc_list_));
    portEXIT_CRITICAL(&obd_mux_);
    dtc_clear_acknowledged_.store(false, std::memory_order_release);
    dtc_clear_requested_.store(true, std::memory_order_release);
    return true;
}

size_t CanManager::getFormattedDtcList(char* out_buffer, size_t max_len, uint8_t& out_count) const {
    out_count = 0;
    if (!out_buffer || max_len == 0) return 0;
    out_buffer[0] = '\0';

    ObdDtcEntry snapshot[MAX_DTC_ENTRIES];
    uint8_t count = 0;

    portENTER_CRITICAL(&obd_mux_);
    count = dtc_count_;
    if (count > MAX_DTC_ENTRIES) count = MAX_DTC_ENTRIES;
    memcpy(snapshot, dtc_list_, count * sizeof(ObdDtcEntry));
    portEXIT_CRITICAL(&obd_mux_);

    size_t pos = 0;
    for (uint8_t i = 0; i < count; i++) {
        int written = snprintf(out_buffer + pos, max_len - pos, "%s,%c\n",
                               snapshot[i].code,
                               snapshot[i].is_pending ? 'P' : 'S');
        if (written <= 0 || pos + static_cast<size_t>(written) >= max_len) {
            break;
        }
        pos += static_cast<size_t>(written);
        out_count++;
    }
    return pos;
}

void CanManager::updateObdQueries() {
    // Strictly never transmit on CAN unless Diagnostic Mode is active
    if (!diag_mode_active_.load(std::memory_order_acquire) ||
        mode_ != OperatingMode::ACTIVE_OBD ||
        !is_running_.load(std::memory_order_acquire) ||
        is_recovering_.load(std::memory_order_acquire)) {
        return;
    }

    if (dtc_clear_requested_.exchange(false, std::memory_order_acq_rel)) {
        sendObdServiceRequest(0x04); // Mode 04: Clear DTCs and reset MIL
        last_query_time_ms_ = millis();
        return;
    }

    if (dtc_scan_requested_.exchange(false, std::memory_order_acq_rel)) {
        sendObdServiceRequest(0x03); // Mode 03: Stored DTCs
        vTaskDelay(pdMS_TO_TICKS(35));
        sendObdServiceRequest(0x07); // Mode 07: Pending DTCs
        last_query_time_ms_ = millis();
        return;
    }

    uint32_t now = millis();
    // Query each Mode 01 PID sequentially every 50 ms (20 Hz query cycle across 4 PIDs = 5 Hz per PID)
    if (now - last_query_time_ms_ >= 50) {
        last_query_time_ms_ = now;
        sendObdRequest(OBD_PID_LIST[current_pid_index_]);
        current_pid_index_ = (current_pid_index_ + 1) % OBD_PID_COUNT;
    }
}

void CanManager::addDtcEntryLocked(uint8_t b1, uint8_t b2, uint8_t is_pending) {
    if (b1 == 0 && b2 == 0) return; // 0x0000 padding is not a DTC
    if (dtc_count_ >= MAX_DTC_ENTRIES) return;

    static const char PREFIXES[4] = { 'P', 'C', 'B', 'U' };
    static const char HEX_CHARS[16] = {
        '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'
    };

    char code[6];
    code[0] = PREFIXES[(b1 >> 6) & 0x03];
    code[1] = static_cast<char>('0' + ((b1 >> 4) & 0x03));
    code[2] = HEX_CHARS[b1 & 0x0F];
    code[3] = HEX_CHARS[(b2 >> 4) & 0x0F];
    code[4] = HEX_CHARS[b2 & 0x0F];
    code[5] = '\0';

    // Deduplicate existing DTC code
    for (uint8_t i = 0; i < dtc_count_; i++) {
        if (strcmp(dtc_list_[i].code, code) == 0) {
            if (!is_pending) {
                dtc_list_[i].is_pending = 0; // Promote to stored if reported by both 03 and 07
            }
            return;
        }
    }

    memcpy(dtc_list_[dtc_count_].code, code, sizeof(code));
    dtc_list_[dtc_count_].is_pending = is_pending;
    dtc_count_++;
}

void CanManager::parseDtcBytesLocked(const uint8_t* bytes, size_t len, uint8_t is_pending) {
    for (size_t i = 0; i + 1 < len; i += 2) {
        addDtcEntryLocked(bytes[i], bytes[i + 1], is_pending);
    }
}

void CanManager::parseObdResponse(const twai_message_t& msg) {
    if (msg.data_length_code < 2) return;

    uint8_t pci_type = msg.data[0] & 0xF0;

    // 1. ISO-TP First Frame (Multi-Frame DTC response: 0x10)
    if (pci_type == 0x10 && msg.data_length_code >= 6) {
        uint8_t service_resp = msg.data[2];
        if (service_resp == 0x43 || service_resp == 0x47) {
            uint8_t is_pending = (service_resp == 0x47) ? 1 : 0;
            portENTER_CRITICAL(&obd_mux_);
            isotp_pending_service_ = service_resp;
            // msg.data[3] is DTC count in ISO 15765-4 CAN; bytes 4..7 hold first two DTCs
            parseDtcBytesLocked(&msg.data[4], msg.data_length_code - 4, is_pending);
            portEXIT_CRITICAL(&obd_mux_);
            sendIsoTpFlowControl(msg.identifier);
        }
        return;
    }

    // 2. ISO-TP Consecutive Frame (0x20..0x2F)
    if (pci_type == 0x20 && msg.data_length_code >= 3) {
        portENTER_CRITICAL(&obd_mux_);
        if (isotp_pending_service_ == 0x43 || isotp_pending_service_ == 0x47) {
            uint8_t is_pending = (isotp_pending_service_ == 0x47) ? 1 : 0;
            parseDtcBytesLocked(&msg.data[1], msg.data_length_code - 1, is_pending);
        }
        portEXIT_CRITICAL(&obd_mux_);
        return;
    }

    // 3. ISO-TP Single Frame (0x00)
    if (pci_type != 0x00) return;
    uint8_t sf_len = msg.data[0] & 0x0F;
    if (sf_len == 0 || sf_len + 1 > msg.data_length_code) return;

    uint8_t service_resp = msg.data[1];

    // Service 04 Positive Response (0x44: DTCs cleared)
    if (service_resp == 0x44) {
        portENTER_CRITICAL(&obd_mux_);
        dtc_count_ = 0;
        memset(dtc_list_, 0, sizeof(dtc_list_));
        portEXIT_CRITICAL(&obd_mux_);
        dtc_clear_acknowledged_.store(true, std::memory_order_release);
        return;
    }

    // Service 03 (0x43 Stored DTCs) or Service 07 (0x47 Pending DTCs) Single Frame
    if (service_resp == 0x43 || service_resp == 0x47) {
        uint8_t is_pending = (service_resp == 0x47) ? 1 : 0;
        if (sf_len >= 2) {
            portENTER_CRITICAL(&obd_mux_);
            // In ISO 15765-4 CAN J1979: data[2] is DTC count, followed by 2-byte DTC pairs (sf_len is even: 2, 4, 6).
            // In legacy KWP-style frames without count byte: sf_len is odd (3, 5, 7) and pairs start at data[2].
            size_t payload_offset = ((sf_len % 2) == 0) ? 3 : 2;
            size_t payload_end = 1 + sf_len;
            if (payload_end > msg.data_length_code) payload_end = msg.data_length_code;
            if (payload_end > payload_offset) {
                parseDtcBytesLocked(&msg.data[payload_offset], payload_end - payload_offset, is_pending);
            }
            portEXIT_CRITICAL(&obd_mux_);
        }
        return;
    }

    // Service 01 (0x41 Live Powertrain Telemetry)
    if (msg.data_length_code < 3 || service_resp != 0x41) return;

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
    if (!diag_mode_active_.load(std::memory_order_acquire)) {
        reconfigureMode(OperatingMode::LISTEN_ONLY);
    }

    Serial.printf("[CAN] Signal %u updated (ID: 0x%03lX, Start: %u, Len: %u, BigEnd: %u, Mult: %.4f, Off: %.1f)\n",
                  signal_id, static_cast<unsigned long>(sanitized.can_id), sanitized.start_byte,
                  sanitized.length_bytes, sanitized.is_big_endian, sanitized.multiplier, sanitized.offset);
}

void CanManager::setProfileActive(bool active, uint16_t baudrate_kbps) {
    portENTER_CRITICAL(&obd_mux_);
    custom_profile_.profile_active = active ? 1 : 0;
    if (baudrate_kbps == 250 || baudrate_kbps == 500 || baudrate_kbps == 1000) {
        custom_profile_.baudrate_kbps = baudrate_kbps;
    } else if (custom_profile_.baudrate_kbps == 0) {
        custom_profile_.baudrate_kbps = 500;
    }
    if (!active) {
        // Clear custom signal active flags when disabling custom profile
        custom_profile_.rpm.is_active = 0;
        custom_profile_.speed.is_active = 0;
        custom_profile_.throttle.is_active = 0;
        custom_profile_.gear.is_active = 0;
        custom_profile_.coolant.is_active = 0;
    }
    portEXIT_CRITICAL(&obd_mux_);

    saveProfileToNvs();
    // Normal operation always stays LISTEN_ONLY unless Diagnostic Mode is currently active
    reconfigureMode(diag_mode_active_.load(std::memory_order_acquire)
                    ? OperatingMode::ACTIVE_OBD
                    : OperatingMode::LISTEN_ONLY);
    Serial.printf("[CAN] Profile active mode set to: %s (Baudrate: %u kbps, TWAI remains LISTEN_ONLY outside Diagnostics)\n",
                  active ? "CUSTOM_CAN" : "PASSIVE_STANDARD", custom_profile_.baudrate_kbps);
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
            if (loaded.baudrate_kbps != 250 && loaded.baudrate_kbps != 500 && loaded.baudrate_kbps != 1000) {
                loaded.baudrate_kbps = 500;
            }
            custom_profile_ = loaded;
            portEXIT_CRITICAL(&obd_mux_);
            Serial.printf("[CAN] Loaded profile from NVS (active: %u, baudrate: %u kbps)\n",
                          loaded.profile_active, loaded.baudrate_kbps);
        } else {
            memset(&custom_profile_, 0, sizeof(custom_profile_));
            custom_profile_.magic = 0x4D4F544F;
            custom_profile_.baudrate_kbps = 500;
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

