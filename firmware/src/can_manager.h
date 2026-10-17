#pragma once

#include <Arduino.h>
#include <atomic>
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
    bool reconfigureMode(OperatingMode new_mode);

    bool receiveFrame(CanFrame& frame, uint32_t wait_ms = 0);
    bool transmitFrame(const CanFrame& frame, uint32_t timeout_ms = 10, bool single_shot = true);

    // Active OBD-II Engine & Dedicated Diagnostic Mode
    void setDiagnosticMode(bool enable);
    bool isDiagnosticModeActive() const {
        return diag_mode_active_.load(std::memory_order_acquire) &&
               (mode_ == OperatingMode::ACTIVE_OBD);
    }
    void updateObdQueries();
    void requestDtcScan();
    bool requestClearDtc();
    size_t getFormattedDtcList(char* out_buffer, size_t max_len, uint8_t& out_count) const;
    ObdTelemetry getTelemetry();

    // Motorcycle Custom CAN Profile (NVS Persistence & Real-Time TWAI decoding)
    void setSignalConfig(uint8_t signal_id, const CanSignalConfig& cfg);
    void setProfileActive(bool active);
    void saveProfileToNvs();
    void loadProfileFromNvs();
    bool isCustomProfileActive() const;
    OperatingMode getOperatingMode() const { return mode_; }
    bool isRunning() const { return is_running_.load(std::memory_order_acquire); }

    // Diagnostics & Statistics
    uint32_t getRxCount() const { return rx_count_.load(std::memory_order_relaxed); }
    uint32_t getTxCount() const { return tx_count_.load(std::memory_order_relaxed); }
    uint32_t getErrorCount() const { return error_count_.load(std::memory_order_relaxed); }
    uint32_t getBusOffCount() const { return bus_off_count_.load(std::memory_order_relaxed); }
    bool isRecovering() const { return is_recovering_.load(std::memory_order_acquire); }
    void handleBusRecovery();

private:
    static constexpr size_t MAX_DTC_ENTRIES = 16;

    OperatingMode mode_;
    std::atomic<bool> diag_mode_active_;
    std::atomic<bool> is_installed_;
    std::atomic<bool> is_running_;
    std::atomic<bool> is_recovering_;
    std::atomic<bool> mode_change_pending_;
    OperatingMode pending_mode_;

    std::atomic<uint32_t> rx_count_;
    std::atomic<uint32_t> tx_count_;
    std::atomic<uint32_t> error_count_;
    std::atomic<uint32_t> bus_off_count_;
    uint32_t last_bus_off_time_ms_;

    ObdTelemetry obd_data_;
    ObdDtcEntry dtc_list_[MAX_DTC_ENTRIES];
    uint8_t dtc_count_;
    uint8_t isotp_pending_service_;
    mutable portMUX_TYPE obd_mux_;

    // Custom Motorcycle CAN Mapping Profile
    EspBikeCanProfile custom_profile_;

    // OBD Request State Machine
    uint8_t current_pid_index_;
    uint32_t last_query_time_ms_;
    std::atomic<bool> dtc_scan_requested_;
    std::atomic<bool> dtc_clear_requested_;
    std::atomic<bool> dtc_clear_acknowledged_;

    bool installAndStartTwai(OperatingMode mode);
    void checkTelemetryTimeoutLocked(uint32_t now_ms);
    void decodeCustomFrame(const twai_message_t& msg);
    float decodeSignalValue(const CanSignalConfig& cfg, const uint8_t* payload, uint8_t dlc);
    void parseObdResponse(const twai_message_t& msg);
    void parseDtcBytesLocked(const uint8_t* bytes, size_t len, uint8_t is_pending);
    void addDtcEntryLocked(uint8_t b1, uint8_t b2, uint8_t is_pending);
    void sendObdRequest(uint8_t pid);
    void sendObdServiceRequest(uint8_t service_id);
    void sendIsoTpFlowControl(uint32_t response_can_id);
    void calculateGear();
};

