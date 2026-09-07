#pragma once

#include <Arduino.h>
#include "driver/twai.h"
#include "config.h"
#include "types.h"

/**
 * @file can_manager.h
 * @brief ESP-IDF TWAI CAN Bus Driver managing Listen-Only passive capture
 *        and active OBD-II Mode 01 diagnostic requests.
 */
class CanManager {
public:
    enum class OperatingMode {
        LISTEN_ONLY,    // Passive sniffer (No ACK, 100% safe on motorcycle bus)
        ACTIVE_OBD      // Active Mode 01 queries (ID 0x7DF / 0x7E8..0x7EF)
    };

    CanManager();
    bool begin(OperatingMode mode = OperatingMode::LISTEN_ONLY);
    void stop();

    bool receiveFrame(CanFrame& frame, uint32_t wait_ms = 0);
    bool transmitFrame(const CanFrame& frame, uint32_t timeout_ms = 10);

    // Active OBD-II Engine
    void updateObdQueries();
    ObdTelemetry getTelemetry();

    // Diagnostics & Statistics
    uint32_t getRxCount() const { return rx_count_; }
    uint32_t getTxCount() const { return tx_count_; }
    uint32_t getErrorCount() const { return error_count_; }

private:
    OperatingMode mode_;
    bool is_installed_;
    bool is_running_;
    uint32_t rx_count_;
    uint32_t tx_count_;
    uint32_t error_count_;

    ObdTelemetry obd_data_;
    portMUX_TYPE obd_mux_;

    // OBD Request State Machine
    uint8_t current_pid_index_;
    uint32_t last_query_time_ms_;

    void parseObdResponse(const twai_message_t& msg);
    void sendObdRequest(uint8_t pid);
    void calculateGear();
};
