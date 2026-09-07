#pragma once

#include <Arduino.h>

/**
 * @file config.h
 * @brief Hardware pinout, system thresholds, and bus configurations
 *        for MotoLogger based on MotoLogger v3.4 + BNO085 breakout.
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
// 2. IMU SUBSYSTEM (CEVA / Hillcrest BNO085 via Native I2C)
// ==============================================================================
constexpr gpio_num_t PIN_IMU_SDA          = GPIO_NUM_1;
constexpr gpio_num_t PIN_IMU_SCL          = GPIO_NUM_2;
constexpr gpio_num_t PIN_IMU_INT          = GPIO_NUM_12; // H_INTN interrupt
constexpr gpio_num_t PIN_IMU_RST          = GPIO_NUM_48; // Active low reset
constexpr uint8_t    BNO085_I2C_ADDR      = 0x4A;        // SA0 tied to GND
constexpr uint32_t   I2C_FREQUENCY_HZ     = 400000;      // 400 kHz Fast-Mode
constexpr uint32_t   IMU_SAMPLE_RATE_HZ   = 100;         // 100 Hz update rate
constexpr uint32_t   IMU_REPORT_MICROS    = 10000;       // 10,000 us (10 ms interval)

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
constexpr float      V_BAT_DIVIDER_RATIO  = 11.0f;       // R18 (120k) / R16 (12k) divider ratio
constexpr float      V_BAT_RUNNING_VOLTS  = 13.0f;       // Engine alternator charging voltage
constexpr float      V_BAT_CUTOFF_VOLTS   = 11.8f;       // Critical discharge cutoff
constexpr uint32_t   AUTO_SHUTDOWN_DELAY_MS = 15000;     // 15 seconds countdown after ignition off

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

// ==============================================================================
// 7. FREERTOS TASK CONFIGURATION (Dual-Core Affinity)
// ==============================================================================
constexpr BaseType_t CORE_CAN_POWER       = 0;           // Core 0: CAN bus, Power & BLE
constexpr BaseType_t CORE_IMU_STORAGE     = 1;           // Core 1: IMU fusion math & SD file I/O

constexpr uint32_t   STACK_CAN_TASK       = 4096;
constexpr uint32_t   STACK_POWER_TASK     = 3072;
constexpr uint32_t   STACK_IMU_TASK       = 4096;
constexpr uint32_t   STACK_STORAGE_TASK   = 8192;
constexpr uint32_t   STACK_BLE_TASK       = 4096;

