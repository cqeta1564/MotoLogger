#pragma once

#include <Arduino.h>

/**
 * @file config.h
 * @brief Hardware pinout, system thresholds, and bus configurations
 *        for MotoLogger based on ESP32-S3 + BNO085 breakout.
 */

// ==============================================================================
// 1. CAN / TWAI BUS (Texas Instruments SN65HVD230)
// ==============================================================================
constexpr gpio_num_t PIN_CAN_TX           = GPIO_NUM_14;
constexpr gpio_num_t PIN_CAN_RX           = GPIO_NUM_13;
constexpr gpio_num_t PIN_CAN_RS           = GPIO_NUM_38; // LOW = High Speed, HIGH = Low Power
constexpr uint32_t   CAN_DEFAULT_BAUDRATE = 500000;      // 500 kbps
constexpr uint32_t   CAN_RX_QUEUE_SIZE    = 256;         // Ring buffer size for CAN messages

// ==============================================================================
// 2. IMU SUBSYSTEM (CEVA / Hillcrest BNO085 via Dedicated HSPI Bus)
// ==============================================================================
constexpr gpio_num_t PIN_IMU_MISO         = GPIO_NUM_1;  // GY-BNO08X SDA/MISO/TX
constexpr gpio_num_t PIN_IMU_SCK          = GPIO_NUM_2;  // GY-BNO08X SCL/SCK/RX
constexpr gpio_num_t PIN_IMU_MOSI         = GPIO_NUM_4;  // GY-BNO08X ADO / ADDR/MOSI
constexpr gpio_num_t PIN_IMU_CS           = GPIO_NUM_5;  // GY-BNO08X CS (Active LOW)
constexpr gpio_num_t PIN_IMU_INT          = GPIO_NUM_12; // GY-BNO08X INT / H_INTN interrupt (Active LOW)
constexpr gpio_num_t PIN_IMU_RST          = GPIO_NUM_48; // GY-BNO08X RST (Active LOW)
constexpr uint32_t   IMU_SPI_SPEED_HZ     = 3000000;     // 3 MHz SPI clock for BNO085
constexpr uint32_t   IMU_SAMPLE_RATE_HZ   = 100;         // 100 Hz update rate
constexpr uint32_t   IMU_REPORT_MICROS    = 10000;       // 10,000 us (10 ms interval)
constexpr uint32_t   IMU_STALE_TIMEOUT_MS = 500;         // Mark IMU offline if no report for 500 ms

// Backward-compatibility aliases
constexpr gpio_num_t PIN_IMU_SDA          = PIN_IMU_MISO;
constexpr gpio_num_t PIN_IMU_SCL          = PIN_IMU_SCK;

// ==============================================================================
// 3. MICROSD CARD INTERFACE (SPI Mode)
// ==============================================================================
constexpr gpio_num_t PIN_SD_CS            = GPIO_NUM_45;
constexpr gpio_num_t PIN_SD_SCK           = GPIO_NUM_39;
constexpr gpio_num_t PIN_SD_MOSI          = GPIO_NUM_40;
constexpr gpio_num_t PIN_SD_MISO          = GPIO_NUM_41;
constexpr uint32_t   SD_SPI_SPEED_MHZ     = 25;          // 25 MHz SPI clock
constexpr size_t     SD_LOG_BUFFER_SIZE   = 32768;       // 32 KB write buffer

// ==============================================================================
// 4. POWER MANAGEMENT & VOLTAGE SENSING
// ==============================================================================
constexpr gpio_num_t PIN_FORCE_ON         = GPIO_NUM_17; // Hold HIGH to keep board powered
constexpr gpio_num_t PIN_3V3_SWITCH       = GPIO_NUM_21; // Switched 3V3 power rail for IMU
constexpr gpio_num_t PIN_SENSE_V_DIG      = GPIO_NUM_8;  // Digital sense: HIGH when alternator runs
constexpr gpio_num_t PIN_SENSE_V_ANA      = GPIO_NUM_9;  // Analog voltage divider sense (ADC1_CH8)

// Automotive voltage thresholds
constexpr float      V_BAT_DIVIDER_RATIO    = 11.0f;     // 1:11 resistor divider ratio
constexpr float      V_BAT_RUNNING_VOLTS    = 13.0f;     // Engine alternator charging voltage
constexpr float      V_BAT_CUTOFF_VOLTS     = 11.8f;     // Critical discharge cutoff
constexpr float      V_BAT_MIN_PRESENT_VOLTS = 6.5f;     // Threshold distinguishing 12V battery from USB-only power
constexpr uint32_t   AUTO_SHUTDOWN_DELAY_MS = 15000;     // 15 seconds countdown after ignition off
constexpr uint32_t   CAN_TELEMETRY_TIMEOUT_MS = 1500;    // Reset stale CAN telemetry after 1.5 s of bus silence

// ==============================================================================
// 5. STATUS INDICATORS
// ==============================================================================
constexpr gpio_num_t PIN_LED_BLUE         = GPIO_NUM_10; // Blue LED: IMU/Storage status & shutdown
constexpr gpio_num_t PIN_LED_YELLOW       = GPIO_NUM_11; // Yellow LED: Power status & CAN activity

// ==============================================================================
// 6. BLUETOOTH LOW ENERGY (BLE) TELEMETRY SERVER
// ==============================================================================
#define BLE_DEVICE_NAME             "MotoLogger-ESP32"
#define BLE_SERVICE_UUID            "19b10000-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_TELEMETRY_UUID     "19b10001-e8f2-537e-4f6c-d104768a1214"
#define BLE_CHAR_COMMAND_UUID       "19b10002-e8f2-537e-4f6c-d104768a1214"
constexpr uint32_t   BLE_STREAM_INTERVAL_MS = 40;        // 25 Hz live stream rate (every 40 ms)

// BLE Commands from Smartphone
constexpr uint8_t CMD_TARE_ZERO         = 0x01;
constexpr uint8_t CMD_TARE_OFFSET       = 0x02;
constexpr uint8_t CMD_SET_CAN_SIGNAL    = 0x03;
constexpr uint8_t CMD_SET_CAN_MODE      = 0x04;
constexpr uint8_t CMD_SYNC_CHECK_LEGACY = 0x05;
constexpr uint8_t CMD_SYNC_REQ_LEGACY   = 0x06;
constexpr uint8_t CMD_SYNC_ACK_LEGACY   = 0x07;
constexpr uint8_t CMD_SYNC_CHECK        = 0x20;
constexpr uint8_t CMD_SYNC_REQUEST_FILE = 0x21;
constexpr uint8_t CMD_SYNC_ACK          = 0x22;
constexpr uint8_t CMD_DIAG_SET_MODE     = 0x30; // 1 = Active OBD-II TX Mode, 0 = Listen-Only RX Mode
constexpr uint8_t CMD_DIAG_READ_DTC     = 0x31; // Query OBD-II Mode 03 & Mode 07 DTC fault codes
constexpr uint8_t CMD_DIAG_CLEAR_DTC    = 0x32; // Clear OBD-II Mode 04 DTC fault codes & MIL
constexpr uint8_t CMD_CAN_SNIFFER_MODE  = 0x40; // 1 = Enable raw CAN sniffer streaming, 0 = Disable

// BLE Responses from ESP32 on Command Characteristic
constexpr uint8_t RESP_SYNC_CHECK        = 0xA0; // 0x20 | 0x80
constexpr uint8_t RESP_SYNC_CHECK_LEGACY = 0x85; // 0x05 | 0x80
constexpr uint8_t RESP_SYNC_CHUNK        = 0xA1; // 0x21 | 0x80
constexpr uint8_t RESP_SYNC_CHUNK_LEGACY = 0x86; // 0x06 | 0x80
constexpr uint8_t RESP_SYNC_ACK          = 0xA2; // 0x22 | 0x80
constexpr uint8_t RESP_SYNC_ACK_LEGACY   = 0x87; // 0x07 | 0x80
constexpr uint8_t RESP_DIAG_MODE         = 0xB0; // 0x30 | 0x80
constexpr uint8_t RESP_DIAG_DTC_LIST     = 0xB1; // 0x31 | 0x80
constexpr uint8_t RESP_DIAG_CLEAR_ACK    = 0xB2; // 0x32 | 0x80
constexpr uint8_t RESP_CAN_RAW_FRAME     = 0xC0; // 0x40 | 0x80 -> [0xC0, id_le(4), dlc(1), data(8)]

// ==============================================================================
// 7. FREERTOS TASK CONFIGURATION (Dual-Core Affinity)
// ==============================================================================
constexpr BaseType_t CORE_CAN_POWER       = 0;           // Core 0: CAN bus, Power & BLE
constexpr BaseType_t CORE_IMU_STORAGE     = 1;           // Core 1: IMU fusion math & SD file I/O

constexpr uint32_t   STACK_CAN_TASK       = 4096;
constexpr uint32_t   STACK_POWER_TASK     = 4096;
constexpr uint32_t   STACK_IMU_TASK       = 6144;
constexpr uint32_t   STACK_STORAGE_TASK   = 8192;
constexpr uint32_t   STACK_BLE_TASK       = 4096;


