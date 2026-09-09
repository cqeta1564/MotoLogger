#include <Arduino.h>
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

// Lock-free queues for inter-task telemetry streaming
static RingBuffer<TelemetryRecord, 512> g_telemetry_queue;
static RingBuffer<CanFrame, 256>        g_raw_can_queue;

// Synchronization flags
static volatile bool g_system_shutdown_ready = false;

// ==============================================================================
// FreeRTOS Task Prototypes
// ==============================================================================
void taskCanBus(void* pvParameters);
void taskImu(void* pvParameters);
void taskStorage(void* pvParameters);
void taskSupervisor(void* pvParameters);
void taskBleStreaming(void* pvParameters);

// ==============================================================================
// BLE Smartphone Command Dispatcher
// ==============================================================================
static void handleBleCommand(uint8_t cmd_id, const uint8_t* payload, size_t length) {
    switch (cmd_id) {
        case 0x01: // Tare zero lean angle & pitch from smartphone app
            g_imu_mgr.tareZero();
            Serial.println("[BLE CMD] IMU Zero-Tare calibrated from mobile app!");
            break;

        case 0x02: // Tare with mounting offset (int16_t tenths of degree)
            if (payload && length >= 2) {
                int16_t offset_x10 = static_cast<int16_t>(payload[0] | (payload[1] << 8));
                float offset_deg = offset_x10 / 10.0f;
                g_imu_mgr.setMountingOffsetDeg(offset_deg);
                Serial.printf("[BLE CMD] IMU mounting offset set to: %.2f deg\n", offset_deg);
            }
            break;

        default:
            Serial.printf("[BLE CMD] Unknown command 0x%02X received.\n", cmd_id);
            break;
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

    // 3. Initialize USB CDC Serial Console
    Serial.begin(115200);
    delay(500);
    Serial.println("\n==============================================");
    Serial.println("  MotoLogger ESP32-S3 Telemetry Starting...   ");
    Serial.println("  MotoLogger + BNO085 + BLE Android/CarPlay");
    Serial.println("==============================================\n");

    // 4. Initialize CAN / TWAI Subsystem (500 kbps, Listen-Only default)
    Serial.print("[CAN] Initializing TWAI (500 kbps, Listen-Only)... ");
    if (g_can_mgr.begin(CanManager::OperatingMode::LISTEN_ONLY)) {
        Serial.println("OK");
    } else {
        Serial.println("FAILED! Retrying in Normal mode...");
        g_can_mgr.begin(CanManager::OperatingMode::ACTIVE_OBD);
    }

    // 5. Initialize BNO085 IMU Subsystem
    Serial.print("[IMU] Initializing BNO085 (I2C 0x4A, 100 Hz GRV)... ");
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
        g_led_indicator.setBluePattern(LedIndicator::Pattern::SLOW_BLINK);
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

    // Core 0: Supervisor & Power Monitor (Normal priority)
    xTaskCreatePinnedToCore(
        taskSupervisor, "Task_Supervisor", STACK_POWER_TASK, nullptr, 2, nullptr, CORE_CAN_POWER
    );

    // Core 1: IMU 100 Hz Fusion Worker (High priority)
    xTaskCreatePinnedToCore(
        taskImu, "Task_IMU", STACK_IMU_TASK, nullptr, 4, nullptr, CORE_IMU_STORAGE
    );

    // Core 1: Storage DMA Writer (Above normal priority)
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
    CanFrame frame;

    while (!g_system_shutdown_ready) {
        if (g_can_mgr.receiveFrame(frame, 5)) {
            g_led_indicator.triggerCanActivity();
            g_raw_can_queue.push(frame);
        }

        g_can_mgr.updateObdQueries();
        taskYIELD();
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 0 Task: High-Speed 25 Hz BLE Telemetry Streamer
// ==============================================================================
void taskBleStreaming(void* pvParameters) {
    const TickType_t interval_ticks = pdMS_TO_TICKS(BLE_STREAM_INTERVAL_MS);
    TickType_t last_wake_time = xTaskGetTickCount();

    while (!g_system_shutdown_ready) {
        if (g_ble_mgr.isConnected()) {
            ImuSample imu = g_imu_mgr.getLatestSample();
            ObdTelemetry obd = g_can_mgr.getTelemetry();
            float v_bat = g_power_mgr.getBatteryVoltage();

            BleTelemetryPacket pkt;
            pkt.timestamp_ms       = millis();
            pkt.lean_angle_x10     = static_cast<int16_t>(imu.roll_deg * 10.0f);
            pkt.pitch_x10          = static_cast<int16_t>(imu.pitch_deg * 10.0f);
            pkt.accel_x_mg         = static_cast<int16_t>(imu.accel_x_g * 1000.0f);
            pkt.accel_y_mg         = static_cast<int16_t>(imu.accel_y_g * 1000.0f);
            pkt.accel_z_mg         = static_cast<int16_t>(imu.accel_z_g * 1000.0f);
            pkt.gyro_x_dps_x10     = static_cast<int16_t>(imu.gyro_x_dps * 10.0f);
            pkt.gyro_y_dps_x10     = static_cast<int16_t>(imu.gyro_y_dps * 10.0f);
            pkt.gyro_z_dps_x10     = static_cast<int16_t>(imu.gyro_z_dps * 10.0f);
            pkt.engine_rpm         = obd.engine_rpm;
            pkt.vehicle_speed_kmh  = obd.vehicle_speed_kmh;
            pkt.throttle_pos_pct   = static_cast<uint8_t>(obd.throttle_pos_pct);
            pkt.coolant_temp_c     = static_cast<int8_t>(obd.coolant_temp_c);
            pkt.gear               = obd.gear;
            pkt.battery_mv         = static_cast<uint16_t>(v_bat * 1000.0f);

            uint8_t flags = 0;
            if (g_storage_mgr.isReady())     flags |= (1 << 0);
            if (g_power_mgr.isEngineRunning()) flags |= (1 << 1);
            if (g_power_mgr.getState() == PowerState::COUNTDOWN_TO_SHUTDOWN) flags |= (1 << 2);
            if (g_imu_mgr.isReady())         flags |= (1 << 3);
            pkt.status_flags       = flags;

            g_ble_mgr.sendTelemetry(pkt);
        }

        vTaskDelayUntil(&last_wake_time, interval_ticks);
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 1 Task: IMU 100 Hz Data Acquisition & Fusion Math
// ==============================================================================
void taskImu(void* pvParameters) {
    ImuSample imu_sample;
    TickType_t last_wake_time = xTaskGetTickCount();
    const TickType_t period_ticks = pdMS_TO_TICKS(10); // 100 Hz = 10 ms

    while (!g_system_shutdown_ready) {
        if (g_imu_mgr.update(imu_sample)) {
            ObdTelemetry obd = g_can_mgr.getTelemetry();

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
        }

        vTaskDelayUntil(&last_wake_time, period_ticks);
    }

    vTaskDelete(nullptr);
}

// ==============================================================================
// Core 1 Task: High-Speed MicroSD Block Writer
// ==============================================================================
void taskStorage(void* pvParameters) {
    TelemetryRecord record;
    CanFrame raw_can;

    while (true) {
        while (g_telemetry_queue.pop(record)) {
            g_storage_mgr.logTelemetry(record);
        }

        while (g_raw_can_queue.pop(raw_can)) {
            g_storage_mgr.logRawCan(raw_can);
        }

        g_storage_mgr.update();

        if (g_power_mgr.isShutdownRequested()) {
            Serial.println("\n[STORAGE] Shutdown requested! Flushing write buffers...");
            g_system_shutdown_ready = true;
            g_storage_mgr.close();
            Serial.printf("[STORAGE] File %s closed safely. Total records: %lu\n", 
                          g_storage_mgr.getCurrentFileName(), 
                          g_storage_mgr.getRecordsWritten());
            
            vTaskDelay(pdMS_TO_TICKS(100));
            Serial.println("[POWER] Dropping latch (FORCE_ON = LOW). Good night!");
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
    uint32_t last_report_ms = 0;

    while (!g_system_shutdown_ready) {
        g_power_mgr.update();

        PowerState pwr_state = g_power_mgr.getState();

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

        // Periodic Serial Diagnostic Telemetry (1 Hz)
        uint32_t now = millis();
        if (now - last_report_ms >= 1000) {
            last_report_ms = now;

            ObdTelemetry obd = g_can_mgr.getTelemetry();
            float v_bat = g_power_mgr.getBatteryVoltage();
            bool engine = g_power_mgr.isEngineRunning();

            Serial.printf("[STAT] Bat: %.2fV (%s) | BLE: %s | CAN RX: %lu | IMU Smp: %lu | SD Rec: %lu | RPM: %u | Spd: %u km/h | Gear: %d",
                v_bat,
                engine ? "RUNNING" : "STOPPED",
                g_ble_mgr.isConnected() ? "CONNECTED" : "ADVERTISING",
                g_can_mgr.getRxCount(),
                g_imu_mgr.getSampleCount(),
                g_storage_mgr.getRecordsWritten(),
                obd.engine_rpm,
                obd.vehicle_speed_kmh,
                obd.gear
            );

            if (pwr_state == PowerState::COUNTDOWN_TO_SHUTDOWN) {
                Serial.printf(" | SHUTDOWN IN: %lu s", g_power_mgr.getShutdownRemainingMs() / 1000);
            }
            Serial.println();
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }

    vTaskDelete(nullptr);
}

