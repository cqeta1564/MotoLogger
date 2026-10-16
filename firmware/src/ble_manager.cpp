#include "ble_manager.h"

class ServerCallbacks : public NimBLEServerCallbacks {
public:
    explicit ServerCallbacks(BleManager* mgr) : mgr_(mgr) {}

    void onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        // Request low connection interval for smooth 25 Hz streaming:
        // min 15 ms (12 * 1.25ms), max 25 ms (20 * 1.25ms), latency 0, 4s timeout
        pServer->updateConnParams(desc->conn_handle, 12, 20, 0, 400);
        mgr_->onClientConnected();
    }

    void onDisconnect(NimBLEServer* pServer) override {
        (void)pServer;
        mgr_->onClientDisconnected();
    }

    void onDisconnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        (void)pServer;
        (void)desc;
        mgr_->onClientDisconnected();
    }

private:
    BleManager* mgr_;
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
public:
    explicit CommandCallbacks(BleManager* mgr) : mgr_(mgr) {}

    void onWrite(NimBLECharacteristic* pCharacteristic) override {
        NimBLEAttValue val = pCharacteristic->getValue();
        if (val.size() > 0) {
            mgr_->onCommandReceived(val.data(), val.size());
        }
    }

private:
    BleManager* mgr_;
};

static ServerCallbacks*  s_server_callbacks  = nullptr;
static CommandCallbacks* s_command_callbacks = nullptr;

BleManager::BleManager()
    : server_(nullptr),
      telemetry_char_(nullptr),
      command_char_(nullptr),
      client_connected_(false),
      packets_sent_(0),
      command_callback_(nullptr) {}

bool BleManager::begin() {
    // 1. Initialize NimBLE stack with custom device name
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Maximum transmit power (+9 dBm for reliable range)
    NimBLEDevice::setMTU(256);              // Negotiate wide ATT MTU for zero-overhead streaming

    // 2. Create GATT Server
    server_ = NimBLEDevice::createServer();
    if (!s_server_callbacks) {
        s_server_callbacks = new ServerCallbacks(this);
    }
    server_->setCallbacks(s_server_callbacks);
    server_->advertiseOnDisconnect(true);

    // 3. Create MotoLogger Telemetry Service
    NimBLEService* service = server_->createService(BLE_SERVICE_UUID);
    if (!service) {
        return false;
    }

    // 4. Create Telemetry Notify/Read Characteristic and pre-populate initial 29-byte frame
    telemetry_char_ = service->createCharacteristic(
        BLE_CHAR_TELEMETRY_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ
    );
    BleTelemetryPacket initial_pkt = {};
    initial_pkt.accel_z_mg = 1000;
    initial_pkt.coolant_temp_c = 20;
    initial_pkt.gear = -1;
    initial_pkt.battery_mv = 12600;
    telemetry_char_->setValue(reinterpret_cast<const uint8_t*>(&initial_pkt), sizeof(initial_pkt));

    // 5. Create Command Characteristic (Bi-directional: Write commands, Notify responses & sync chunks)
    command_char_ = service->createCharacteristic(
        BLE_CHAR_COMMAND_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ
    );
    if (!s_command_callbacks) {
        s_command_callbacks = new CommandCallbacks(this);
    }
    command_char_->setCallbacks(s_command_callbacks);

    // 6. Start Service
    service->start();

    // 7. Setup and start Advertising
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(BLE_SERVICE_UUID);
    adv->setName(BLE_DEVICE_NAME);
    adv->setScanResponse(true);
    adv->start();

    return true;
}

void BleManager::onClientConnected() {
    client_connected_.store(true, std::memory_order_release);
}

void BleManager::onClientDisconnected() {
    client_connected_.store(false, std::memory_order_release);
    NimBLEDevice::startAdvertising();
}

void BleManager::onCommandReceived(const uint8_t* data, size_t length) {
    if (!data || length == 0) return;
    uint8_t cmd_id = data[0];
    const uint8_t* payload = (length > 1) ? &data[1] : nullptr;
    size_t payload_len = (length > 1) ? (length - 1) : 0;

    if (command_callback_) {
        command_callback_(cmd_id, payload, payload_len);
    }
}

bool BleManager::isSubscribed() const {
    return client_connected_.load(std::memory_order_acquire) &&
           telemetry_char_ &&
           (telemetry_char_->getSubscribedCount() > 0);
}

bool BleManager::isCommandSubscribed() const {
    return client_connected_.load(std::memory_order_acquire) &&
           command_char_ &&
           (command_char_->getSubscribedCount() > 0);
}

bool BleManager::sendCommandResponse(const uint8_t* data, size_t length) {
    if (!client_connected_.load(std::memory_order_acquire) || !command_char_) {
        return false;
    }
    command_char_->setValue(data, length);
    command_char_->notify();
    return true;
}

void BleManager::sendTelemetry(const BleTelemetryPacket& packet) {
    if (!client_connected_.load(std::memory_order_acquire) ||
        !telemetry_char_ ||
        telemetry_char_->getSubscribedCount() == 0) {
        return;
    }

    telemetry_char_->setValue(reinterpret_cast<const uint8_t*>(&packet), sizeof(packet));
    telemetry_char_->notify();
    packets_sent_.fetch_add(1, std::memory_order_relaxed);
}

void BleManager::update() {
    // NimBLE handles connections asynchronously via internal FreeRTOS event queues
}

