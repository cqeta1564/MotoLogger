# MotoLogger: ESP32-S3 Motorcycle Telemetry Datalogger

[![PlatformIO](https://img.shields.io/badge/PlatformIO-Compatible-orange.svg)](https://platformio.org/)
[![ESP32-S3](https://img.shields.io/badge/MCU-ESP32--S3-red.svg)](https://www.espressif.com/)
[![CAN-Bus](https://img.shields.io/badge/CAN-500kbps_TWAI-blue.svg)](https://www.ti.com/)
[![IMU](https://img.shields.io/badge/IMU-BNO085_9DoF-green.svg)](https://www.ceva-dsp.com/)
[![BLE](https://img.shields.io/badge/BLE-25Hz_GATT_Stream-purple.svg)](https://github.com/h2zero/NimBLE-Arduino)

High-performance, modular C++ firmware and hardware package for motorcycle telemetry datalogging based on the custom **MotoLogger v3.4 (ESP32-S3)** design paired with a **CEVA / Hillcrest BNO085 9-DoF IMU** breakout module and **NimBLE real-time streaming** to Android (Android Auto) and iOS (Apple CarPlay).

---

## Repository Structure

```
MotoLogger-Firmware/
├── hardware/                                # Complete PCB fabrication & assembly files
│   ├── gerbers/                             # Production-ready Gerber ZIP archives
│   │   ├── MotoLogger_v3.4_Clean_Gerber.zip # Main board gerbers (neutral silkscreen)
│   │   └── MotoLogger_OBD2_Plug_Gerber.zip  # OBD-II sandwich connector gerbers
│   ├── assembly/                            # SMT / PCBA manufacturing data
│   │   ├── MotoLogger_v3.4_BOM.csv          # Bill of Materials with LCSC part numbers
│   │   ├── MotoLogger_v3.4_BOM.xlsx         # Formatted Excel BOM
│   │   ├── MotoLogger_v3.4_Part_Placements.zip # Top and bottom SMT placement files
│   │   └── Ordering_Specs_JLCPCB_PCBWay.md  # Detailed fabrication and assembly specs
│   └── schematics/                          # Circuit schematics and reference
│       ├── MotoLogger_v3.4_Schematic.png    # High-resolution circuit schematic diagram
│       ├── MotoLogger_v3.4_Schematic.json   # Full circuit schematic source
│       └── MotoLogger_Pinout_Reference.h    # Header pad mapping reference
├── include/
│   ├── config.h                             # Hardware pinout, BLE UUIDs, thresholds
│   ├── types.h                              # Telemetry data models & BleTelemetryPacket
│   └── ring_buffer.h                        # Lock-free SPSC circular buffer
└── src/
    ├── main.cpp                             # FreeRTOS scheduler & task coordination
    ├── ble_manager.h/.cpp                   # 25 Hz NimBLE GATT Server (Android/CarPlay)
    ├── can_manager.h/.cpp                   # 500 kbps TWAI CAN driver (Listen-Only + OBD)
    ├── imu_manager.h/.cpp                   # BNO085 100 Hz Game Rotation Vector fusion
    ├── power_manager.h/.cpp                 # 12V latch, switched 3.3V rail & auto-shutdown
    ├── storage_manager.h/.cpp               # 32 KB buffered MicroSD logging
    └── led_indicator.h/.cpp                 # Diagnostic LED patterns (Yellow/Blue)
```

---

## Key Features

- **Dual-Core FreeRTOS Architecture:**
  - **Core 0:** TWAI (CAN bus) driver, Power Supervisor, and 25 Hz NimBLE telemetry stream.
  - **Core 1:** 100 Hz BNO085 Game Rotation Vector fusion math & MicroSD block logging.
- **Vibration-Immune Lean Angle (Roll) & Pitch:**
  - Utilizes BNO085 **Game Rotation Vector** (accelerometer + gyro fusion).
  - Eliminates compass/magnetometer distortion caused by motorcycle ignition coils, alternators, and steel frames.
- **500 kbps TWAI CAN Bus Engine:**
  - **Passive Sniffer (Listen-Only):** 100% safe, non-intrusive monitoring of all motorcycle broadcast frames.
  - **Active Diagnostic Mode:** Automatic querying of standard OBD-II Mode 01 PIDs (RPM, Vehicle Speed, Throttle %, Coolant Temp, Gear estimation).
  - High-speed transceiver control with slope control (`PIN_CAN_RS = GPIO38` held LOW).
- **25 Hz BLE Real-Time Streaming (Android Auto & Apple CarPlay Ready):**
  - Ultra-lightweight **NimBLE-Arduino** stack running simultaneously with Wi-Fi-based CarPlay/Android Auto.
  - 28-byte packed binary packet transmitted via BLE notifications for zero parsing overhead on mobile.
  - Two-way command characteristic for remote zero-calibration (Tare Zero) from the phone app.
- **Lossless Buffered MicroSD Logging:**
  - Double-buffered 32 KB RAM queue decouples SD block-erase latency spikes from real-time CAN/IMU streams.
  - Generates synchronized 100 Hz CSV files (`LOG_0001.CSV`, `LOG_0002.CSV`...) ready for MoTeC i2, RaceRender, and TrackAddict analysis.
- **Automotive Power Management & Zero Parasitic Drain:**
  - Automatic latching via `FORCE_ON` (`GPIO17`).
  - Digital engine-run detection (`SENSE_V_DIG` `GPIO8`) + ADC battery voltage sensing (`SENSE_V_ANA` `GPIO9`).
  - Configurable 15-second grace period after ignition shutoff to safely flush and close files.
  - Drops power latch to achieve **0 mA quiescent current** from the 12V battery when parked.

---

## Hardware Pinout (MotoLogger v3.4 + BNO085)

| Periphery / Function | ESP32-S3 Pin | Signal / Description |
| :--- | :--- | :--- |
| **CAN TX** | `GPIO14` | SN65HVD230 Transceiver TX |
| **CAN RX** | `GPIO13` | SN65HVD230 Transceiver RX |
| **CAN RS** | `GPIO38` | Transceiver Mode (LOW = High Speed 500k, HIGH = Standby) |
| **IMU SDA** | `GPIO1` | BNO085 Native I2C Data (400 kHz) |
| **IMU SCL** | `GPIO2` | BNO085 Native I2C Clock |
| **IMU INT (H_INTN)**| `GPIO12` | BNO085 Data-Ready Interrupt (Active LOW) |
| **IMU RST** | `GPIO48` | BNO085 Hardware Reset (Active LOW) |
| **3V3 Switch Rail** | `GPIO21` | Switched 3.3V power rail (MT9700 load switch) |
| **MicroSD CS** | `GPIO45` | SPI Chip Select |
| **MicroSD SCK** | `GPIO39` | SPI Clock (25 MHz) |
| **MicroSD MOSI** | `GPIO40` | SPI Master Out Slave In |
| **MicroSD MISO** | `GPIO41` | SPI Master In Slave Out |
| **Power Latch** | `GPIO17` | `FORCE_ON` - Keep HIGH to maintain power from 12V |
| **Digital Battery Sense**| `GPIO8` | `SENSE_V_DIG` - HIGH when engine is running/charging |
| **Analog Battery Sense** | `GPIO9` | `SENSE_V_ANA` - ADC with 1:11 resistor divider |
| **Blue LED** | `GPIO10` | IMU / MicroSD status / Auto-shutdown countdown |
| **Yellow LED** | `GPIO11` | Power rail status / CAN frame burst flash |

---

## BLE GATT Protocol Specification

- **Device Name:** `MotoLogger-ESP32`
- **Service UUID:** `19B10000-E8F2-537E-4F6C-D104768A1214`
- **Telemetry Characteristic (Notify / Read):** `19B10001-E8F2-537E-4F6C-D104768A1214`
- **Command Characteristic (Write):** `19B10002-E8F2-537E-4F6C-D104768A1214`

### Binary Packet Structure (28 bytes)
```c
struct __attribute__((packed)) BleTelemetryPacket {
    uint32_t timestamp_ms;       // Monotonic timestamp (ms)
    int16_t  lean_angle_x10;     // Roll * 10 (e.g. -452 = -45.2 deg lean)
    int16_t  pitch_x10;          // Pitch * 10 (e.g. +51 = +5.1 deg)
    int16_t  accel_x_mg;         // Longitudinal G * 1000 (+1000 = +1.0G accel)
    int16_t  accel_y_mg;         // Lateral G * 1000
    int16_t  accel_z_mg;         // Vertical G * 1000
    int16_t  gyro_x_dps_x10;     // Roll rate * 10 (deg/s * 10)
    int16_t  gyro_y_dps_x10;     // Pitch rate * 10 (deg/s * 10)
    int16_t  gyro_z_dps_x10;     // Yaw rate * 10 (deg/s * 10)
    uint16_t engine_rpm;         // RPM (0 - 20000)
    uint8_t  vehicle_speed_kmh;  // Speed (0 - 255 km/h)
    uint8_t  throttle_pos_pct;   // Throttle (0 - 100 %)
    int8_t   coolant_temp_c;     // Engine coolant temp (-40 .. +150 C)
    int8_t   gear;               // Calculated gear (-1 = unknown, 0 = N, 1..6)
    uint16_t battery_mv;         // Battery voltage (e.g. 14250 = 14.25 V)
    uint8_t  status_flags;       // Bit 0: SD, Bit 1: Engine run, Bit 2: Countdown, Bit 3: IMU ok
};
```

### Commands (Phone -> ESP32)
Write 1 byte to Command Characteristic `19B10002-...`:
- `0x01`: **Zero-Tare Calibration** (vynuluje aktuální náklon a pitch jako horizontální referenci).

---

## CSV Telemetry File Format (SD Card)

Columns in `LOG_XXXX.CSV`:
```csv
timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,v_bat,engine_rpm,vehicle_speed_kmh,throttle_pos_pct,coolant_temp_c,gear
```

---

## Building and Flashing

### Build via PlatformIO CLI
```bash
cd MotoLogger-Firmware
pio run
pio run --target upload
pio device monitor
```

---

## License
Open-source under MIT License.
