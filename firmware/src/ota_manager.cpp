#include "ota_manager.h"

static const char OTA_INDEX_HTML[] PROGMEM = R"rawhtml(
<!DOCTYPE html>
<html lang="cs">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MotoLogger · Aktualizace firmwaru (OTA)</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: #F2F2F7;
      color: #1C1C1E;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
      box-sizing: border-box;
    }
    .card {
      background: #FFFFFF;
      border-radius: 16px;
      padding: 28px;
      max-width: 420px;
      width: 100%;
      box-shadow: 0 4px 20px rgba(0,0,0,0.06);
      border: 1px solid #E5E5EA;
    }
    h1 {
      font-size: 22px;
      margin-top: 0;
      margin-bottom: 8px;
      font-weight: 700;
    }
    p {
      font-size: 14px;
      color: #636366;
      line-height: 1.5;
      margin-bottom: 20px;
    }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      background: #E8F2FF;
      color: #0066CC;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 600;
      margin-bottom: 16px;
    }
    input[type=file] {
      width: 100%;
      padding: 12px;
      border: 1px dashed #C7C7CC;
      border-radius: 12px;
      background: #F9F9FB;
      box-sizing: border-box;
      margin-bottom: 20px;
      font-size: 14px;
    }
    button {
      width: 100%;
      height: 54px;
      background: #0066CC;
      color: #FFFFFF;
      border: none;
      border-radius: 14px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: opacity 0.2s;
    }
    button:disabled {
      background: #AEAEB2;
      cursor: not-allowed;
    }
    #progress {
      display: none;
      margin-top: 16px;
      text-align: center;
      font-size: 14px;
      font-weight: 600;
      color: #0066CC;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">MotoLogger ESP32-S3</div>
    <h1>Aktualizace firmwaru</h1>
    <p>Vyberte binární soubor firmwaru (.bin) zkompilovaný v PlatformIO. Během nahrávání nevypínejte napájení motocyklu.</p>
    <form id="upload_form" method="POST" action="/update" enctype="multipart/form-data">
      <input type="file" name="update" accept=".bin" required onchange="document.getElementById('subBtn').disabled = false;">
      <button type="submit" id="subBtn" disabled>Nahrát nový firmware</button>
    </form>
    <div id="progress">Nahrávám firmware, vyčkejte prosím…</div>
  </div>
  <script>
    document.getElementById('upload_form').onsubmit = function() {
      document.getElementById('subBtn').disabled = true;
      document.getElementById('progress').style.display = 'block';
    };
  </script>
</body>
</html>
)rawhtml";

OtaManager::OtaManager()
    : is_active_(false),
      state_(OtaState::OFF),
      ap_ip_(0, 0, 0, 0),
      server_(80),
      status_cb_(nullptr) {}

void OtaManager::begin(OtaStatusCallback status_cb) {
    status_cb_ = status_cb;
    WiFi.mode(WIFI_OFF);
    state_ = OtaState::OFF;
    is_active_ = false;
}

void OtaManager::notifyStatus(OtaState state) {
    state_ = state;
    if (status_cb_) {
        status_cb_(state_, ap_ip_);
    }
}

void OtaManager::setupRoutes() {
    server_.on("/", HTTP_GET, [this]() {
        server_.send_P(200, "text/html", OTA_INDEX_HTML);
    });

    server_.on("/update", HTTP_POST, [this]() {
        server_.sendHeader("Connection", "close");
        if (Update.hasError()) {
            server_.send(500, "text/plain", "OTA Failed!");
            notifyStatus(OtaState::ERROR_REJECTED);
        } else {
            server_.send(200, "text/plain", "OK. Rebooting...");
            notifyStatus(OtaState::SUCCESS_REBOOTING);
            delay(1000);
            ESP.restart();
        }
    }, [this]() {
        HTTPUpload& upload = server_.upload();
        if (upload.status == UPLOAD_FILE_START) {
            Serial.printf("[OTA] Update Start: %s\n", upload.filename.c_str());
            notifyStatus(OtaState::UPDATING);
            if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                Update.printError(Serial);
                notifyStatus(OtaState::ERROR_REJECTED);
            }
        } else if (upload.status == UPLOAD_FILE_WRITE) {
            if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
                Update.printError(Serial);
                notifyStatus(OtaState::ERROR_REJECTED);
            }
        } else if (upload.status == UPLOAD_FILE_END) {
            if (Update.end(true)) {
                Serial.printf("[OTA] Update Success: %u bytes\n", upload.totalSize);
            } else {
                Update.printError(Serial);
                notifyStatus(OtaState::ERROR_REJECTED);
            }
        } else if (upload.status == UPLOAD_FILE_ABORTED) {
            Update.end();
            Serial.println("[OTA] Update Aborted");
            notifyStatus(OtaState::ERROR_REJECTED);
        }
    });
}

bool OtaManager::startOtaAp() {
    if (is_active_) return true;

    Serial.println("[OTA] Starting SoftAP (SSID: MotoLogger-OTA)...");
    WiFi.mode(WIFI_AP);
    bool ap_ok = WiFi.softAP("MotoLogger-OTA", "motologger");
    if (!ap_ok) {
        Serial.println("[OTA] Failed to start SoftAP!");
        notifyStatus(OtaState::ERROR_REJECTED);
        return false;
    }

    ap_ip_ = WiFi.softAPIP();
    Serial.printf("[OTA] SoftAP Ready. IP: %s\n", ap_ip_.toString().c_str());

    setupRoutes();
    server_.begin();
    is_active_ = true;
    notifyStatus(OtaState::READY_WAITING);
    return true;
}

void OtaManager::stopOtaAp() {
    if (!is_active_) return;

    Serial.println("[OTA] Stopping SoftAP and WebServer...");
    server_.stop();
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_OFF);
    is_active_ = false;
    ap_ip_ = IPAddress(0, 0, 0, 0);
    notifyStatus(OtaState::OFF);
}

void OtaManager::handleClient() {
    if (is_active_) {
        server_.handleClient();
    }
}
