#include <Arduino.h>
#include <math.h>
#include <stdarg.h>
#include <atomic>
#include "config.h"
#include "types.h"
#include "ring_buffer.h"
#include "power_manager.h"
#include "can_manager.h"
#include "imu_manager.h"
#include "storage_manager.h"
#include "ble_manager.h"
#include "led_indicator.h"

// ==============================================================================
// Global Subsystem Instances
// ==============================================================================
static PowerManager   g_power_mgr;
static CanManager     g_can_mgr;
static ImuManager     g_imu_mgr;
static StorageManager g_storage_mgr;
static BleManager     g_ble_mgr;
static LedIndicator   g_led_indicator;
static SemaphoreHandle_t g_serial_mutex = nullptr;

// Lock-free queues for inter-task telemetry streaming & BLE command offloading
static RingBuffer<TelemetryRecord, 512> g_telemetry_queue;
static RingBuffer<CanFrame, 256>        g_raw_can_queue;
static RingBuffer<BleCommandEvent, 16>  g_ble_cmd_queue;

// Synchronization flags
static std::atomic<bool> g_system_shutdown_ready{false};

// ==============================================================================
// FreeRTOS Task Prototypes
// ==============================================================================
void taskCanBus(void* pvParameters);
void taskImu(void* pvParameters);
void taskStorage(void* pvParameters);
void taskSupervisor(void* pvParameters);
void taskBleStreaming(void* pvParameters);

// ==============================================================================
// Thread-Safe Serial Logging Helper
// ==============================================================================
static void logPrintf(const char* fmt, ...) {
    char buf[256];
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    if (n <= 0) return;

    if (g_serial_mutex && xSemaphoreTake(g_serial_mutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        Serial.print(buf);
        xSemaphoreGive(g_serial_mutex);
    } else if (!g_serial_mutex) {
        Serial.print(buf);
    }
}

// ==============================================================================
// Fixed-Point Clamping & Rounding Helpers for BLE Telemetry Packet
// ==============================================================================
static inline int16_t clampRoundInt16(float value, float scale, int16_t min_val, int16_t max_val) {
    if (!isfinite(value)) return 0;
    long scaled = lroundf(value * scale);
    if (scaled < static_cast<long>(min_val)) return min_val;
    if (scaled > static_cast<long>(max_val)) return max_val;
    return static_cast<int16_t>(scaled);
}

static inline uint16_t clampRoundUint16(float value, float scale, uint16_t max_val) {
    if (!isfinite(value) || value <= 0.0f) return 0;
    long scaled = lroundf(value * scale);
    if (scaled < 0) return 0;
    if (scaled > static_cast<long>(max_val)) return max_val;
    return static_cast<uint16_t>(scaled);
}

static inline uint8_t clampRoundUint8(float value, uint8_t max_val) {
    if (!isfinite(value) || value <= 0.0f) return 0;
    long rounded = lroundf(value);
    if (rounded < 0) return 0;
    if (rounded > static_cast<long>(max_val)) return max_val;
    return static_cast<uint8_t>(rounded);
}

static inline int8_t clampInt8(int32_t value, int8_t min_val, int8_t max_val) {
    if (value < static_cast<int32_t>(min_val)) return min_val;
    if (value > static_cast<int32_t>(max_val)) return max_val;
    return static_cast<int8_t>(value);
}

// ==============================================================================
// Non-Blocking BLE Command Enqueue (Runs inside NimBLE GATT Callback)
// ==============================================================================
static void handleBleCommand(uint8_t cmd_id, const uint8_t* payload, size_t length) {
    BleCommandEvent ev = {};
    ev.command_id = cmd_id;
    size_t copy_len = (length > sizeof(ev.payload)) ? sizeof(ev.payload) : length;
    ev.length = static_cast<uint8_t>(copy_len);
    if (payload && copy_len > 0) {
        memcpy(ev.payload, payload, copy_len);
    }
    g_ble_cmd_queue.push(ev);
}

// ==============================================================================
// BLE Command Worker (Executed safely on Task_Supervisor outside NimBLE ISR/Host)
// ==============================================================================
static void processBleCommandQueue() {
    BleCommandEvent ev;
    while (g_ble_cmd_queue.pop(ev)) {
        const uint8_t* payload = ev.payload;
        size_t length = ev.length;

        switch (ev.command_id) {
            case 0x01: // Tare zero lean angle & pitch from smartphone app
                g_imu_mgr.tareZero();
                logPrintf("[BLE CMD] IMU Zero-Tare calibrated from mobile app!\n");
                break;

            case 0x02: // Tare with mounting roll offset in tenths of a degree (int16_t, little-endian)
                if (length >= 2) {
                    int16_t offset_x10 = static_cast<int16_t>(
                        static_cast<uint16_t>(payload[0]) | (static_cast<uint16_t>(payload[1]) << 8)
                    );
                    float offset_deg = static_cast<float>(offset_x10) / 10.0f;
                    g_imu_mgr.setRollOffset(offset_deg);
                    logPrintf("[BLE CMD] Tare mounting offset calibrated: %.2f deg (saved to NVS)\n", offset_deg);
                } else {
                    logPrintf("[BLE CMD] Invalid payload length for Tare Offset: %u\n", static_cast<unsigned int>(length));
                }
                break;

            case 0x03: // Configure CAN signal mapping (saved to NVS)
                if (length >= 16) {
                    uint8_t signal_id = payload[0];
                    CanSignalConfig cfg = {};
                    memcpy(&cfg.can_id, &payload[1], 4);
                    cfg.start_byte = payload[5];
                    cfg.length_bytes = payload[6];
                    cfg.is_big_endian = payload[7];
                    cfg.is_active = 1;
                    memcpy(&cfg.multiplier, &payload[8], 4);
                    memcpy(&cfg.offset, &payload[12], 4);

                    g_can_mgr.setSignalConfig(signal_id, cfg);
                    logPrintf("[BLE CMD] CAN signal %u configured and saved to NVS.\n", signal_id);
                } else {
                    logPrintf("[BLE CMD] Invalid payload length for CAN Signal Config: %u\n", static_cast<unsigned int>(length));
                }
                break;

            case 0x04: // Set CAN profile active mode (1 = Custom profile, 0 = Standard OBD)
                if (length >= 1) {
                    bool active = (payload[0] != 0);
                    g_can_mgr.setProfileActive(active);
                    logPrintf("[BLE CMD] CAN profile active mode: %s (saved to NVS)\n", active ? "CUSTOM" : "OBD");
                } else {
                    logPrintf("[BLE CMD] Invalid payload length for CAN Profile Mode: %u\n", static_cast<unsigned int>(length));
                }
                break;

            case CMD_SYNC_CHECK_LEGACY:
            case CMD_SYNC_CHECK: {
                uint8_t count = 0;
                char list_buf[256] = {};
                size_t list_len = g_storage_mgr.getUnsyncedSessionFiles(list_buf, sizeof(list_buf) - 2, count);

                uint8_t resp_buf[256];
                resp_buf[0] = (ev.command_id == CMD_SYNC_CHECK) ? RESP_SYNC_CHECK : RESP_SYNC_CHECK_LEGACY;
                resp_buf[1] = count;
                if (list_len > 0) {
                    memcpy(&resp_buf[2], list_buf, list_len);
                }
                g_ble_mgr.sendCommandResponse(resp_buf, 2 + list_len);
                logPrintf("[BLE CMD] Offline sync check: found %u unsynced files (%u bytes list)\n",
                          static_cast<unsigned int>(count), static_cast<unsigned int>(list_len));
                break;
            }

            case CMD_SYNC_REQ_LEGACY:
            case CMD_SYNC_REQUEST_FILE: {
                char req_name[33] = {};
                if (length > 0) {
                    size_t copy_len = (length < 32) ? length : 32;
                    memcpy(req_name, payload, copy_len);
                    req_name[copy_len] = '\0';
                }

                uint8_t resp_opcode = (ev.command_id == CMD_SYNC_REQUEST_FILE) ? RESP_SYNC_CHUNK : RESP_SYNC_CHUNK_LEGACY;

                logPrintf("[BLE CMD] Offline log download requested: %s\n", req_name[0] ? req_name : "(none)");

                if (!req_name[0] || !g_storage_mgr.openStreamingFile(req_name)) {
                    logPrintf("[BLE CMD] Failed to open %s for streaming!\n", req_name);
                    uint8_t err_pkt[4] = { resp_opcode, 0x00, 0x00, 0xFF };
                    g_ble_mgr.sendCommandResponse(err_pkt, sizeof(err_pkt));
                    break;
                }

                uint16_t seq = 0;
                bool is_eof = false;
                uint8_t chunk_payload[180];
                size_t bytes_read = 0;
                uint32_t total_streamed = 0;

                while (!is_eof && g_ble_mgr.isConnected() && !g_system_shutdown_ready.load(std::memory_order_acquire)) {
                    bool ok = g_storage_mgr.readStreamingChunk(chunk_payload, sizeof(chunk_payload), bytes_read, is_eof);
                    if (!ok) {
                        uint8_t err_pkt[4] = {
                            resp_opcode,
                            static_cast<uint8_t>(seq & 0xFF),
                            static_cast<uint8_t>((seq >> 8) & 0xFF),
                            0xFF
                        };
                        g_ble_mgr.sendCommandResponse(err_pkt, sizeof(err_pkt));
                        break;
                    }

                    uint8_t pkt[4 + sizeof(chunk_payload)];
                    pkt[0] = resp_opcode;
                    pkt[1] = static_cast<uint8_t>(seq & 0xFF);
                    pkt[2] = static_cast<uint8_t>((seq >> 8) & 0xFF);
                    pkt[3] = is_eof ? 0x01 : 0x00;
                    if (bytes_read > 0) {
                        memcpy(&pkt[4], chunk_payload, bytes_read);
                    }

                    g_ble_mgr.sendCommandResponse(pkt, 4 + bytes_read);
                    total_streamed += bytes_read;
                    seq++;

                    // Keep supervisor power monitor and LED patterns alive during long file transfers
                    if ((seq % 3) == 0) {
                        ObdTelemetry obd = g_can_mgr.getTelemetry();
                        g_power_mgr.update(g_ble_mgr.isConnected(), obd.engine_rpm);
                        g_led_indicator.update();
                    }

                    // 15 ms delay yields CPU to FreeRTOS (BLE task, CAN task, Supervisor)
                    vTaskDelay(pdMS_TO_TICKS(15));
                }

                g_storage_mgr.closeStreamingFile();
                logPrintf("[BLE CMD] Streamed %lu bytes (%u chunks, eof=%d) for %s\n",
                          static_cast<unsigned long>(total_streamed),
                          static_cast<unsigned int>(seq),
                          is_eof ? 1 : 0,
                          req_name);
                break;
            }

            case CMD_SYNC_ACK_LEGACY:
            case CMD_SYNC_ACK: {
                char ack_name[33] = {};
                if (length > 0) {
                    size_t copy_len = (length < 32) ? length : 32;
                    memcpy(ack_name, payload, copy_len);
                    ack_name[copy_len] = '\0';
                }
                if (ack_name[0]) {
                    g_storage_mgr.markSessionSynced(ack_name);
                } else {
                    g_storage_mgr.acknowledgeSessionSynced(nullptr);
                }

                uint8_t resp_opcode = (ev.command_id == CMD_SYNC_ACK) ? RESP_SYNC_ACK : RESP_SYNC_ACK_LEGACY;
                uint8_t ack_resp[2] = { resp_opcode, 0x01 };
                g_ble_mgr.sendCommandResponse(ack_resp, sizeof(ack_resp));

                logPrintf("[BLE CMD] Offline log sync acknowledged (%s).\n", ack_name[0] ? ack_name : "current");
                break;
            }

            case CMD_DIAG_SET_MODE: {
                bool enable = (length >= 1) && (payload[0] != 0);
                ObdTelemetry obd = g_can_mgr.getTelemetry();
                if (enable && obd.vehicle_speed_kmh > 5) {
                    logPrintf("[BLE CMD] Diagnostic mode DENIED (Speed = %u km/h > 5 km/h safety limit).\n",
                              obd.vehicle_speed_kmh);
                    enable = false;
                }

                g_can_mgr.setDiagnosticMode(enable);
                // Allow Task_CAN to execute the TWAI mode reconfiguration on Core 0
                vTaskDelay(pdMS_TO_TICKS(60));

                bool active = g_can_mgr.isDiagnosticModeActive();
                uint8_t resp[2] = { RESP_DIAG_MODE, static_cast<uint8_t>(active ? 1 : 0) };
                g_ble_mgr.sendCommandResponse(resp, sizeof(resp));
                logPrintf("[BLE CMD] Diagnostic mode %s (CAN mode: %s)\n",
                          active ? "ENABLED" : "DISABLED",
                          active ? "ACTIVE_OBD (TX+RX)" : "LISTEN_ONLY (RX only)");
                break;
            }

            case CMD_DIAG_READ_DTC: {
                ObdTelemetry obd = g_can_mgr.getTelemetry();
                if (!g_can_mgr.isDiagnosticModeActive()) {
                    if (obd.vehicle_speed_kmh <= 5) {
                        g_can_mgr.setDiagnosticMode(true);
                        vTaskDelay(pdMS_TO_TICKS(60));
                    } else {
                        logPrintf("[BLE CMD] DTC read DENIED (Speed = %u km/h > 5 km/h).\n", obd.vehicle_speed_kmh);
                        uint8_t err_resp[2] = { RESP_DIAG_DTC_LIST, 0x00 };
                        g_ble_mgr.sendCommandResponse(err_resp, sizeof(err_resp));
                        break;
                    }
                }

                g_can_mgr.requestDtcScan();
                // Wait up to 250 ms for Task_CAN to transmit Service 0x03 & 0x07 and receive ECU ISO-TP frames
                vTaskDelay(pdMS_TO_TICKS(250));

                uint8_t dtc_count = 0;
                char dtc_buf[240] = {};
                size_t dtc_len = g_can_mgr.getFormattedDtcList(dtc_buf, sizeof(dtc_buf) - 2, dtc_count);

                uint8_t resp[244];
                resp[0] = RESP_DIAG_DTC_LIST;
                resp[1] = dtc_count;
                if (dtc_len > 0) {
                    memcpy(&resp[2], dtc_buf, dtc_len);
                }
                g_ble_mgr.sendCommandResponse(resp, 2 + dtc_len);
                logPrintf("[BLE CMD] OBD-II DTC scan complete: %u fault(s) (%s)\n",
                          static_cast<unsigned int>(dtc_count),
                          dtc_len > 0 ? dtc_buf : "none");
                break;
            }

            case CMD_DIAG_CLEAR_DTC: {
                ObdTelemetry obd = g_can_mgr.getTelemetry();
                if (!g_can_mgr.isDiagnosticModeActive()) {
                    if (obd.vehicle_speed_kmh <= 5) {
                        g_can_mgr.setDiagnosticMode(true);
                        vTaskDelay(pdMS_TO_TICKS(60));
                    } else {
                        logPrintf("[BLE CMD] DTC clear DENIED (Speed = %u km/h > 5 km/h).\n", obd.vehicle_speed_kmh);
                        uint8_t err_resp[2] = { RESP_DIAG_CLEAR_ACK, 0x00 };
                        g_ble_mgr.sendCommandResponse(err_resp, sizeof(err_resp));
                        break;
                    }
                }

                bool requested = g_can_mgr.requestClearDtc();
                if (requested) {
                    vTaskDelay(pdMS_TO_TICKS(200));
                }

                uint8_t resp[2] = { RESP_DIAG_CLEAR_ACK, static_cast<uint8_t>(requested ? 1 : 0) };
                g_ble_mgr.sendCommandResponse(resp, sizeof(resp));
                logPrintf("[BLE CMD] OBD-II Clear DTC (Service 04) %s.\n",
                          requested ? "transmitted" : "rejected");
                break;
            }

            default:
                logPrintf("[BLE CMD] Unknown command 0x%02X received.\n", ev.command_id);
                break;
        }
    }
}

// ==============================================================================
// Arduino setup()
// ==============================================================================
void setup() {
    // 1. Initialize Power Manager and latch supply IMMEDIATELY
    g_power_mgr.begin();

    // 2. Initialize Status LEDs
    g_led_indicator.begin();
    g_led_indicator.setYellowPattern(LedIndicator::Pattern::SOLID_ON);
    g_led_indicator.setBluePattern(LedIndicator::Pattern::FAST_BLINK);

    // 3. Initialize Thread-Safe Mutex & USB CDC Serial Console
    g_serial_mutex = xSemaphoreCreateMutex();
    Serial.begin(115200);
    delay(500);
    Serial.println("\n==============================================");
    Serial.println("  MotoLogger ESP32-S3 Telemetry Starting...   ");
    Serial.println("  MotoLogger v3.4 + BNO085 + BLE Android/CarPlay");
    Serial.println("==============================================\n");

    // 4. Initialize CAN / TWAI Subsystem (500 kbps; ALWAYS boots in Listen-Only passive mode)
    Serial.print("[CAN] Initializing TWAI (500 kbps)... ");
    if (g_can_mgr.begin(CanManager::OperatingMode::LISTEN_ONLY)) {
        Serial.println("OK (Listen-Only / Passive Safe Mode)");
    } else {
        Serial.println("FAILED!");
    }

    // 5. Initialize BNO085 IMU Subsystem
    Serial.print("[IMU] Initializing BNO085 (SPI 3 MHz, 100 Hz GRV)... ");
    if (g_imu_mgr.begin()) {
        Serial.println("OK");
    } else {
        Serial.println("FAILED! Check wiring & 3V3 switch rail.");
        g_led_indicator.setBluePattern(LedIndicator::Pattern::ERROR_BLINK);
    }

    // 6. Initialize MicroSD Storage Subsystem
    Serial.print("[SD] Mounting MicroSD & opening session file... ");
    if (g_storage_mgr.begin()) {
        Serial.printf("OK -> %s\n", g_storage_mgr.getCurrentFileName());
        if (g_imu_mgr.isReady()) {
            g_led_indicator.setBluePattern(LedIndicator::Pattern::SLOW_BLINK);
        }
    } else {
        Serial.println("FAILED! Check MicroSD card insertion.");
        g_led_indicator.setBluePattern(LedIndicator::Pattern::ERROR_BLINK);
    }

    // 7. Initialize BLE Telemetry GATT Server
    Serial.print("[BLE] Starting NimBLE Telemetry Server (MotoLogger-ESP32)... ");
    g_ble_mgr.setCommandCallback(handleBleCommand);
    if (g_ble_mgr.begin()) {
        Serial.println("OK (Advertising)");
    } else {
        Serial.println("FAILED!");
    }

    // 8. Launch FreeRTOS Tasks with Dual-Core Affinity
    Serial.println("[RTOS] Spawning multi-core worker tasks...");

    // Core 0: CAN Bus Worker (High priority)
    xTaskCreatePinnedToCore(
        taskCanBus, "Task_CAN", STACK_CAN_TASK, nullptr, 5, nullptr, CORE_CAN_POWER
    );

    // Core 0: 25 Hz BLE Streaming Worker (Normal priority)
    xTaskCreatePinnedToCore(
        taskBleStreaming, "Task_BLE", STACK_BLE_TASK, nullptr, 3, nullptr, CORE_CAN_POWER
    );

    // Core 0: Supervisor & Power Monitor (Low priority)
    xTaskCreatePinnedToCore(
        taskSupervisor, "Task_Supervisor", STACK_POWER_TASK, nullptr, 2, nullptr, CORE_CAN_POWER
    );

    // Core 1: IMU 100 Hz Fusion Worker (High priority)
    xTaskCreatePinnedToCore(
        taskImu, "Task_IMU", STACK_IMU_TASK, nullptr, 4, nullptr, CORE_IMU_STORAGE
    );

    // Core 1: Storage DMA Writer (Normal priority)
    xTaskCreatePinnedToCore(
        taskStorage, "Task_Storage", STACK_STORAGE_TASK, nullptr, 3, nullptr, CORE_IMU_STORAGE
    );

    Serial.println("[SYSTEM] All tasks running. Logging & BLE active.\n");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}

// ==============================================================================
// Core 0 Task: CAN Bus Message Processor
// ==============================================================================
void taskCanBus(void* pvParameters) {
    (void)pvParameters;
    CanFrame frame;

    while (!g_system_shutdown_ready.load(std::memory_order_acquire)) {
        // Wait up to 5 ms for the first incoming CAN frame
        if (g_can_mgr.receiveFrame(frame, 5)) {
            g_led_indicator.triggerCanActivity();
            g_raw_can_queue.push(frame);

            // Drain up to 31 additional queued frames non-blockingly
            uint8_t burst_count = 1;
            while (burst_count < 32 && g_can_mgr.receiveFrame(frame, 0)) {
                g_raw_can_queue.push(frame);
                burst_count++;
            }

            // If a full burst of 32 frames arrived continuously, yield 1 tick
            // so lower-priority tasks (BLE, Supervisor, IDLE0) are never starved
            if (burst_count >= 32) {
                vTaskDelay(1);
            }
        }

        g_can_mgr.updateObdQueries();
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 0 Task: High-Speed 25 Hz BLE Telemetry Streamer
// ==============================================================================
void taskBleStreaming(void* pvParameters) {
    (void)pvParameters;
    const TickType_t interval_ticks = pdMS_TO_TICKS(BLE_STREAM_INTERVAL_MS);
    TickType_t last_wake_time = xTaskGetTickCount();

    while (!g_system_shutdown_ready.load(std::memory_order_acquire)) {
        if (g_ble_mgr.isConnected()) {
            ImuSample imu = g_imu_mgr.getLatestSample();
            ObdTelemetry obd = g_can_mgr.getTelemetry();
            float v_bat = g_power_mgr.getBatteryVoltage();

            BleTelemetryPacket pkt = {};
            pkt.timestamp_ms       = millis();
            pkt.lean_angle_x10     = clampRoundInt16(imu.roll_deg,   10.0f,   -1800,  1800);
            pkt.pitch_x10          = clampRoundInt16(imu.pitch_deg,  10.0f,   -900,   900);
            pkt.accel_x_mg         = clampRoundInt16(imu.accel_x_g,  1000.0f, -16000, 16000);
            pkt.accel_y_mg         = clampRoundInt16(imu.accel_y_g,  1000.0f, -16000, 16000);
            pkt.accel_z_mg         = clampRoundInt16(imu.accel_z_g,  1000.0f, -16000, 16000);
            pkt.gyro_x_dps_x10     = clampRoundInt16(imu.gyro_x_dps, 10.0f,   -20000, 20000);
            pkt.gyro_y_dps_x10     = clampRoundInt16(imu.gyro_y_dps, 10.0f,   -20000, 20000);
            pkt.gyro_z_dps_x10     = clampRoundInt16(imu.gyro_z_dps, 10.0f,   -20000, 20000);
            pkt.engine_rpm         = obd.engine_rpm;
            pkt.vehicle_speed_kmh  = obd.vehicle_speed_kmh;
            pkt.throttle_pos_pct   = clampRoundUint8(obd.throttle_pos_pct, 100);
            pkt.coolant_temp_c     = clampInt8(obd.coolant_temp_c, -40, 127);
            pkt.gear               = clampInt8(obd.gear, -1, 8);
            pkt.battery_mv         = clampRoundUint16(v_bat, 1000.0f, 65535);

            uint8_t flags = 0;
            if (g_storage_mgr.isReady())           flags |= STATUS_FLAG_SD_READY;
            if (g_power_mgr.isEngineRunning())     flags |= STATUS_FLAG_ENGINE_RUNNING;
            if (g_power_mgr.getState() == PowerState::COUNTDOWN_TO_SHUTDOWN) {
                flags |= STATUS_FLAG_SHUTDOWN_COUNTDOWN;
            }
            if (g_imu_mgr.isReady())               flags |= STATUS_FLAG_IMU_READY;
            if (g_can_mgr.isDiagnosticModeActive()) flags |= STATUS_FLAG_DIAG_ACTIVE;
            pkt.status_flags       = flags;

            g_ble_mgr.sendTelemetry(pkt);
        }

        TickType_t now_ticks = xTaskGetTickCount();
        if (now_ticks - last_wake_time >= interval_ticks) {
            last_wake_time = now_ticks;
        }
        vTaskDelayUntil(&last_wake_time, interval_ticks);
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 1 Task: IMU 100 Hz Data Acquisition & Fusion Math
// ==============================================================================
void taskImu(void* pvParameters) {
    (void)pvParameters;
    ImuSample imu_sample{};
    TickType_t last_wake_time = xTaskGetTickCount();
    const TickType_t period_ticks = pdMS_TO_TICKS(10); // 100 Hz = 10 ms

    while (!g_system_shutdown_ready.load(std::memory_order_acquire)) {
        // 1. Poll IMU sensor (updates internal sample and attempts auto-reconnect if offline)
        bool has_new_imu = g_imu_mgr.update(imu_sample);
        if (!has_new_imu) {
            imu_sample = g_imu_mgr.getLatestSample();
        }

        // 2. Fetch latest vehicle CAN telemetry
        ObdTelemetry obd = g_can_mgr.getTelemetry();

        // 3. Assemble unified 100 Hz telemetry record
        TelemetryRecord record;
        record.timestamp_ms      = millis();
        record.lean_angle_deg    = imu_sample.roll_deg;
        record.pitch_deg         = imu_sample.pitch_deg;
        record.accel_x_g         = imu_sample.accel_x_g;
        record.accel_y_g         = imu_sample.accel_y_g;
        record.accel_z_g         = imu_sample.accel_z_g;
        record.gyro_x_dps        = imu_sample.gyro_x_dps;
        record.gyro_y_dps        = imu_sample.gyro_y_dps;
        record.gyro_z_dps        = imu_sample.gyro_z_dps;
        record.battery_voltage   = g_power_mgr.getBatteryVoltage();
        record.engine_rpm        = obd.engine_rpm;
        record.vehicle_speed_kmh = obd.vehicle_speed_kmh;
        record.throttle_pos_pct  = obd.throttle_pos_pct;
        record.coolant_temp_c    = obd.coolant_temp_c;
        record.gear              = obd.gear;

        g_telemetry_queue.push(record);

        // Resynchronize wake timer if an SPI reconnect attempt exceeded one 10 ms period
        TickType_t now_ticks = xTaskGetTickCount();
        if (now_ticks - last_wake_time >= period_ticks) {
            last_wake_time = now_ticks;
        }
        vTaskDelayUntil(&last_wake_time, period_ticks);
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 1 Task: High-Speed MicroSD Block Writer
// ==============================================================================
void taskStorage(void* pvParameters) {
    (void)pvParameters;
    TelemetryRecord record;
    CanFrame raw_can;

    while (true) {
        if (g_storage_mgr.isReady()) {
            while (g_telemetry_queue.pop(record)) {
                g_storage_mgr.logTelemetry(record);
            }

            while (g_raw_can_queue.pop(raw_can)) {
                g_storage_mgr.logRawCan(raw_can);
            }
        } else {
            // Keep queues clean while SD is unmounted so hot-plug starts with fresh samples
            g_telemetry_queue.reset();
            g_raw_can_queue.reset();
        }

        g_storage_mgr.update();

        if (g_power_mgr.isShutdownRequested()) {
            logPrintf("\n[STORAGE] Shutdown requested! Draining queues and flushing write buffers...\n");
            g_system_shutdown_ready.store(true, std::memory_order_release);
            vTaskDelay(pdMS_TO_TICKS(20));

            if (g_storage_mgr.isReady()) {
                while (g_telemetry_queue.pop(record)) {
                    g_storage_mgr.logTelemetry(record);
                }
                while (g_raw_can_queue.pop(raw_can)) {
                    g_storage_mgr.logRawCan(raw_can);
                }
            }

            g_storage_mgr.close();
            g_can_mgr.stop();

            logPrintf("[STORAGE] File %s closed safely. Total records: %lu\n",
                      g_storage_mgr.getCurrentFileName(),
                      static_cast<unsigned long>(g_storage_mgr.getRecordsWritten()));

            vTaskDelay(pdMS_TO_TICKS(100));
            logPrintf("[POWER] Dropping latch (FORCE_ON = LOW). Good night!\n");
            Serial.flush();
            g_power_mgr.forcePowerOff();

            while (true) {
                vTaskDelay(pdMS_TO_TICKS(1000));
            }
        }

        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

// ==============================================================================
// Core 0 Task: Supervisor, Power State Machine & Telemetry Diagnostics
// ==============================================================================
void taskSupervisor(void* pvParameters) {
    (void)pvParameters;
    uint32_t last_report_ms = 0;
    bool prev_ble_connected = false;

    while (!g_system_shutdown_ready.load(std::memory_order_acquire)) {
        // 1. Process any queued BLE commands outside the NimBLE host callback
        processBleCommandQueue();

        // 2. Log BLE connection state transitions cleanly & enforce Diagnostic Mode safety interlock
        bool ble_conn = g_ble_mgr.isConnected();
        if (ble_conn != prev_ble_connected) {
            prev_ble_connected = ble_conn;
            if (ble_conn) {
                logPrintf("[BLE] Smartphone connected! Telemetry stream ready.\n");
            } else {
                if (g_can_mgr.isDiagnosticModeActive()) {
                    g_can_mgr.setDiagnosticMode(false);
                    logPrintf("[CAN] BLE disconnected -> Diagnostic mode automatically disabled (returned to Listen-Only).\n");
                }
                logPrintf("[BLE] Smartphone disconnected. Advertising restarted.\n");
            }
        }

        // 3. Feed power state machine with live connectivity and CAN RPM data
        ObdTelemetry obd = g_can_mgr.getTelemetry();
        g_power_mgr.update(ble_conn, obd.engine_rpm);

        PowerState pwr_state = g_power_mgr.getState();

        // 4. Update LED diagnostic patterns
        if (!g_storage_mgr.isReady() || !g_imu_mgr.isReady()) {
            g_led_indicator.setBluePattern(LedIndicator::Pattern::ERROR_BLINK);
        } else if (pwr_state == PowerState::COUNTDOWN_TO_SHUTDOWN) {
            g_led_indicator.setBluePattern(LedIndicator::Pattern::FAST_BLINK);
        } else {
            g_led_indicator.setBluePattern(LedIndicator::Pattern::SLOW_BLINK);
        }

        if (g_power_mgr.isEngineRunning()) {
            g_led_indicator.setYellowPattern(LedIndicator::Pattern::SOLID_ON);
        } else {
            g_led_indicator.setYellowPattern(LedIndicator::Pattern::SLOW_BLINK);
        }

        g_led_indicator.update();

        // 5. Periodic Serial Diagnostic Telemetry (1 Hz)
        uint32_t now = millis();
        if (now - last_report_ms >= 1000) {
            last_report_ms = now;

            float v_bat = g_power_mgr.getBatteryVoltage();
            bool engine = g_power_mgr.isEngineRunning();

            if (pwr_state == PowerState::COUNTDOWN_TO_SHUTDOWN) {
                logPrintf(
                    "[STAT] Bat: %.2fV (%s) | BLE: %s | CAN RX: %lu (Off: %lu) | IMU Smp: %lu | SD Rec: %lu | RPM: %u | Spd: %u km/h | Gear: %d | SHUTDOWN IN: %lu s\n",
                    v_bat,
                    engine ? "RUNNING" : "STOPPED",
                    ble_conn ? (g_ble_mgr.isSubscribed() ? "STREAMING" : "CONNECTED") : "ADVERTISING",
                    static_cast<unsigned long>(g_can_mgr.getRxCount()),
                    static_cast<unsigned long>(g_can_mgr.getBusOffCount()),
                    static_cast<unsigned long>(g_imu_mgr.getSampleCount()),
                    static_cast<unsigned long>(g_storage_mgr.getRecordsWritten()),
                    obd.engine_rpm,
                    obd.vehicle_speed_kmh,
                    obd.gear,
                    static_cast<unsigned long>(g_power_mgr.getShutdownRemainingMs() / 1000)
                );
            } else {
                logPrintf(
                    "[STAT] Bat: %.2fV (%s) | BLE: %s | CAN RX: %lu (Off: %lu) | IMU Smp: %lu | SD Rec: %lu | RPM: %u | Spd: %u km/h | Gear: %d\n",
                    v_bat,
                    engine ? "RUNNING" : "STOPPED",
                    ble_conn ? (g_ble_mgr.isSubscribed() ? "STREAMING" : "CONNECTED") : "ADVERTISING",
                    static_cast<unsigned long>(g_can_mgr.getRxCount()),
                    static_cast<unsigned long>(g_can_mgr.getBusOffCount()),
                    static_cast<unsigned long>(g_imu_mgr.getSampleCount()),
                    static_cast<unsigned long>(g_storage_mgr.getRecordsWritten()),
                    obd.engine_rpm,
                    obd.vehicle_speed_kmh,
                    obd.gear
                );
            }
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }

    vTaskDelete(nullptr);
}


