#pragma once

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <atomic>
#include "config.h"
#include "types.h"

/**
 * @file ble_manager.h
 * @brief Manages BLE GATT Server for streaming real-time 25 Hz telemetry
 *        to Android (Android Auto) and iOS (Apple CarPlay) smartphones.
 */
class BleManager {
public:
    typedef void (*CommandCallback)(uint8_t command_id, const uint8_t* payload, size_t length);

    BleManager();
    bool begin();
    void update();
    void sendTelemetry(const BleTelemetryPacket& packet);
    bool sendCommandResponse(const uint8_t* data, size_t length);
    bool isConnected() const { return client_connected_.load(std::memory_order_acquire); }
    bool isSubscribed() const;
    bool isCommandSubscribed() const;
    uint32_t getPacketsSent() const { return packets_sent_.load(std::memory_order_relaxed); }
    void setCommandCallback(CommandCallback cb) { command_callback_ = cb; }

    // Callbacks accessed by NimBLE internal handlers
    void onClientConnected();
    void onClientDisconnected();
    void onCommandReceived(const uint8_t* data, size_t length);

private:
    NimBLEServer*         server_;
    NimBLECharacteristic* telemetry_char_;
    NimBLECharacteristic* command_char_;
    std::atomic<bool>     client_connected_;
    std::atomic<uint32_t> packets_sent_;
    CommandCallback       command_callback_;
};

