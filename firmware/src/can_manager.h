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

    // Active OBD-II Engine
    void updateObdQueries();
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
    OperatingMode mode_;
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
    mutable portMUX_TYPE obd_mux_;

    // Custom Motorcycle CAN Mapping Profile
    EspBikeCanProfile custom_profile_;

    // OBD Request State Machine
    uint8_t current_pid_index_;
    uint32_t last_query_time_ms_;

    bool installAndStartTwai(OperatingMode mode);
    void checkTelemetryTimeoutLocked(uint32_t now_ms);
    void decodeCustomFrame(const twai_message_t& msg);
    float decodeSignalValue(const CanSignalConfig& cfg, const uint8_t* payload, uint8_t dlc);
    void parseObdResponse(const twai_message_t& msg);
    void sendObdRequest(uint8_t pid);
    void calculateGear();
};

