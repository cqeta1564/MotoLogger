#include "ble_manager.h"

class ServerCallbacks : public NimBLEServerCallbacks {
public:
    ServerCallbacks(BleManager* mgr) : mgr_(mgr) {}
    void onConnect(NimBLEServer* pServer) override {
        mgr_->onClientConnected();
    }
    void onDisconnect(NimBLEServer* pServer) override {
        mgr_->onClientDisconnected();
    }
private:
    BleManager* mgr_;
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
public:
    CommandCallbacks(BleManager* mgr) : mgr_(mgr) {}
    void onWrite(NimBLECharacteristic* pCharacteristic) override {
        std::string val = pCharacteristic->getValue();
        if (!val.empty()) {
            mgr_->onCommandReceived(reinterpret_cast<const uint8_t*>(val.data()), val.size());
        }
    }
private:
    BleManager* mgr_;
};

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

    // 2. Create GATT Server
    server_ = NimBLEDevice::createServer();
    server_->setCallbacks(new ServerCallbacks(this));

    // 3. Create MotoLogger Telemetry Service
    NimBLEService* service = server_->createService(BLE_SERVICE_UUID);
    if (!service) {
        return false;
    }

    // 4. Create Telemetry Notify Characteristic
    telemetry_char_ = service->createCharacteristic(
        BLE_CHAR_TELEMETRY_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ
    );

    // 5. Create Command Write Characteristic (Zero tare, lap mark, config)
    command_char_ = service->createCharacteristic(
        BLE_CHAR_COMMAND_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    command_char_->setCallbacks(new CommandCallbacks(this));

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
    client_connected_ = true;
    Serial.println("[BLE] Smartphone connected! Telemetry stream ready.");
}

void BleManager::onClientDisconnected() {
    client_connected_ = false;
    Serial.println("[BLE] Smartphone disconnected. Restarting advertising...");
    NimBLEDevice::startAdvertising();
}

void BleManager::onCommandReceived(const uint8_t* data, size_t length) {
    if (length == 0) return;
    uint8_t cmd_id = data[0];
    const uint8_t* payload = (length > 1) ? &data[1] : nullptr;
    size_t payload_len = (length > 1) ? (length - 1) : 0;

    Serial.printf("[BLE] Command received: 0x%02X (len %u)\n", cmd_id, length);

    if (command_callback_) {
        command_callback_(cmd_id, payload, payload_len);
    }
}

void BleManager::sendTelemetry(const BleTelemetryPacket& packet) {
    if (!client_connected_ || !telemetry_char_) return;

    telemetry_char_->setValue(reinterpret_cast<const uint8_t*>(&packet), sizeof(packet));
    telemetry_char_->notify();
    packets_sent_++;
}

void BleManager::update() {
    // NimBLE handles connections asynchronously via internal FreeRTOS event queues
}
