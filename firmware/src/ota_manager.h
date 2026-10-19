#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Update.h>
#include <atomic>
#include <functional>
#include "types.h"

/**
 * @file ota_manager.h
 * @brief Wireless on-demand Wi-Fi SoftAP firmware update manager with embedded web flasher.
 */
class OtaManager {
public:
    using OtaStatusCallback = std::function<void(OtaState state, IPAddress ip)>;

    OtaManager();

    void begin(OtaStatusCallback status_cb = nullptr);
    bool startOtaAp();
    void stopOtaAp();
    void handleClient();

    bool isOtaActive() const { return is_active_.load(std::memory_order_acquire); }
    OtaState getState() const { return state_; }
    IPAddress getIp() const { return ap_ip_; }

    void setStateCallback(OtaStatusCallback cb) { status_cb_ = cb; }

private:
    void notifyStatus(OtaState state);
    void setupRoutes();

    std::atomic<bool> is_active_;
    bool routes_configured_;
    OtaState state_;
    IPAddress ap_ip_;
    WebServer server_;
    OtaStatusCallback status_cb_;
};

