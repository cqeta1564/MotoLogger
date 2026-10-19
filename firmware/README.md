# MotoLogger: ESP32-S3 Motorcycle Telemetry Datalogger

[![PlatformIO](https://img.shields.io/badge/PlatformIO-Compatible-orange.svg)](https://platformio.org/)
[![ESP32-S3](https://img.shields.io/badge/MCU-ESP32--S3-red.svg)](https://www.espressif.com/)
[![CAN-Bus](https://img.shields.io/badge/CAN-500kbps_TWAI-blue.svg)](https://www.ti.com/)
[![IMU](https://img.shields.io/badge/IMU-BNO085_9DoF-green.svg)](https://www.ceva-dsp.com/)
[![BLE](https://img.shields.io/badge/BLE-25Hz_GATT_Stream-purple.svg)](https://github.com/h2zero/NimBLE-Arduino)

High-performance, modular C++ firmware and hardware package for motorcycle telemetry datalogging based on the custom **MotoLogger (ESP32-S3)** design paired with a **CEVA / Hillcrest BNO085 9-DoF IMU** breakout module and **NimBLE real-time streaming** to Android (Android Auto) and iOS (Apple CarPlay).

---

## Repository Structure

```
MotoLogger-Firmware/
├── hardware/                                # Complete PCB fabrication & assembly files
│   ├── gerbers/                             # Production-ready Gerber ZIP archives
│   │   ├── MotoLogger_Clean_Gerber.zip      # Main board gerbers (neutral silkscreen)
│   │   └── MotoLogger_OBD2_Plug_Gerber.zip  # OBD-II sandwich connector gerbers
│   ├── assembly/                            # SMT / PCBA manufacturing data
│   │   ├── MotoLogger_BOM.csv               # Bill of Materials with LCSC part numbers
│   │   ├── MotoLogger_BOM.xlsx              # Formatted Excel BOM
│   │   ├── MotoLogger_Part_Placements.zip   # Top and bottom SMT placement files
│   │   └── Ordering_Specs_JLCPCB_PCBWay.md  # Detailed fabrication and assembly specs
│   └── schematics/                          # Circuit schematics and reference
│       ├── MotoLogger_Schematic.png         # High-resolution circuit schematic diagram
│       ├── MotoLogger_Schematic.json        # Full circuit schematic source
│       └── MotoLogger_Pinout_Reference.h    # Header pad mapping reference
├── include/
│   ├── config.h                             # Hardware pinout, BLE UUIDs, thresholds
│   ├── types.h                              # Telemetry data models & BleTelemetryPacket
│   └── ring_buffer.h                        # Lock-free SPSC circular buffer
└── src/
    ├── main.cpp                             # FreeRTOS scheduler & task coordination
    ├── ble_manager.h/.cpp                   # 25 Hz NimBLE GATT Server (Android/CarPlay)
    ├── can_manager.h/.cpp                   # 500 kbps TWAI CAN driver (Listen-Only + OBD)
    ├── imu_manager.h/.cpp                   # BNO085 100 Hz Game Rotation Vector fusion (HSPI 3 MHz)
    ├── ota_manager.h/.cpp                   # On-demand Wi-Fi SoftAP Web OTA firmware flasher
    ├── power_manager.h/.cpp                 # 12V latch, switched 3.3V rail & auto-shutdown
    ├── storage_manager.h/.cpp               # 32 KB buffered MicroSD logging (FSPI 25 MHz)
    └── led_indicator.h/.cpp                 # Diagnostic LED patterns (Yellow/Blue)
```

---

## Key Features

- **Dual-Core FreeRTOS Architecture:**
  - **Core 0:** TWAI (CAN bus) driver, Power Supervisor, and 25 Hz NimBLE telemetry stream.
  - **Core 1:** 100 Hz BNO085 Game Rotation Vector fusion math & MicroSD block logging.
- **Vibration-Immune Lean Angle (Roll) & Pitch (Dedicated HSPI @ 3 MHz):**
  - Utilizes BNO085 **Game Rotation Vector** (accelerometer + gyro fusion).
  - Eliminates compass/magnetometer distortion caused by motorcycle ignition coils, alternators, and steel frames.
  - High-speed 4-wire SPI eliminates I2C clock-stretching stalls and EMI noise spikes.
- **500 kbps Automotive TWAI CAN Bus Engine:**
  - **Passive Sniffer (Listen-Only):** 100% safe, non-intrusive monitoring of all motorcycle broadcast frames.
  - **Live Baudrate Switch:** Supports 250 kbps, 500 kbps, and 1000 kbps live reconfiguration.
  - **Active Diagnostic Mode:** Automatic querying of standard OBD-II Mode 01 PIDs and Mode 03/07 DTC fault code read & clear.
  - High-speed transceiver control with slope control (`PIN_CAN_RS = GPIO38` held LOW).
- **25 Hz BLE Real-Time Streaming (Android Auto & Apple CarPlay Ready):**
  - Ultra-lightweight **NimBLE-Arduino** stack running simultaneously with Wi-Fi-based CarPlay/Android Auto.
  - 29-byte packed binary packet transmitted via BLE notifications for zero parsing overhead on mobile.
  - Two-way command characteristic for remote zero-calibration, CAN signal mapping, sniffer streaming, and OTA trigger.
- **Wireless On-Demand Wi-Fi OTA Maintenance Mode:**
  - On-demand SoftAP (`MotoLogger-OTA`, IP `192.168.4.1`) with built-in web flasher.
  - Strict motion interlock: OTA mode is rejected if vehicle speed > 5 km/h.
- **Lossless Buffered MicroSD Logging:**
  - Double-buffered 32 KB RAM queue decouples SD block-erase latency spikes from real-time CAN/IMU streams.
  - Generates synchronized 100 Hz CSV files (`LOG_0001.CSV`, `LOG_0002.CSV`...) ready for MoTeC i2, RaceRender, and TrackAddict analysis.
- **Automotive Power Management & Zero Parasitic Drain:**
  - Automatic latching via `FORCE_ON` (`GPIO17`).
  - Digital engine-run detection (`SENSE_V_DIG` `GPIO8`) + ADC battery voltage sensing (`SENSE_V_ANA` `GPIO9`).
  - Configurable 15-second grace period after ignition shutoff to safely flush and close files.
  - Drops power latch to achieve **0 mA quiescent current** from the 12V battery when parked.

---

## Hardware Pinout (MotoLogger + BNO085)

| Periphery / Function | ESP32-S3 Pin | Signal / Description |
| :--- | :--- | :--- |
| **CAN TX** | `GPIO14` | SN65HVD230 Transceiver TX |
| **CAN RX** | `GPIO13` | SN65HVD230 Transceiver RX |
| **CAN RS** | `GPIO38` | Transceiver Mode (LOW = Active 500k/250k/1M, HIGH = Standby) |
| **IMU MISO** | `GPIO1` | BNO085 HSPI MISO (GY-BNO08X `SDA/MISO/TX`) |
| **IMU SCK** | `GPIO2` | BNO085 HSPI Clock (3 MHz) (GY-BNO08X `SCL/SCK/RX`) |
| **IMU MOSI** | `GPIO4` | BNO085 HSPI MOSI (GY-BNO08X `ADDR/MOSI`, or pad `GPIO6` on custom PCB) |
| **IMU CS** | `GPIO5` | BNO085 HSPI Chip Select (GY-BNO08X `CS`, or pad `GPIO47` on custom PCB) |
| **IMU INT (H_INTN)**| `GPIO12` | BNO085 SHTP Interrupt / Data-Ready (Active LOW) |
| **IMU RST** | `GPIO48` | BNO085 Hardware Reset (Active LOW) |
| **3V3 Switch Rail** | `GPIO21` | Switched 3.3V power rail (MT9700 load switch) |
| **MicroSD CS** | `GPIO45` | SPI Chip Select (Dedicated FSPI bus) |
| **MicroSD SCK** | `GPIO39` | SPI Clock (25 MHz) |
| **MicroSD MOSI** | `GPIO40` | SPI Master Out Slave In |
| **MicroSD MISO** | `GPIO41` | SPI Master In Slave Out |
| **Power Latch** | `GPIO17` | `FORCE_ON` - Keep HIGH to maintain power from 12V |
| **Digital Battery Sense**| `GPIO8` | `SENSE_V_DIG` - HIGH when alternator is charging |
| **Analog Battery Sense** | `GPIO9` | `SENSE_V_ANA` - ADC with 1:11 resistor divider |
| **Blue LED** | `GPIO10` | IMU / MicroSD status / Auto-shutdown countdown |
| **Yellow LED** | `GPIO11` | Power rail status / CAN frame burst flash |

---

## BLE GATT Protocol Specification

- **Device Name:** `MotoLogger-ESP32`
- **Service UUID:** `19B10000-E8F2-537E-4F6C-D104768A1214`
- **Telemetry Characteristic (Notify / Read):** `19B10001-E8F2-537E-4F6C-D104768A1214`
- **Command Characteristic (Write / Notify):** `19B10002-E8F2-537E-4F6C-D104768A1214`

### Binary Packet Structure (29 bytes)
```c
struct __attribute__((packed)) BleTelemetryPacket {
    uint32_t timestamp_ms;       // Offset 0..3:   Monotonic timestamp (ms)
    int16_t  lean_angle_x10;     // Offset 4..5:   Roll * 10 (e.g. -452 = -45.2 deg lean)
    int16_t  pitch_x10;          // Offset 6..7:   Pitch * 10 (e.g. +51 = +5.1 deg)
    int16_t  accel_x_mg;         // Offset 8..9:   Longitudinal G * 1000 (+1000 = +1.0G accel)
    int16_t  accel_y_mg;         // Offset 10..11: Lateral G * 1000
    int16_t  accel_z_mg;         // Offset 12..13: Vertical G * 1000
    int16_t  gyro_x_dps_x10;     // Offset 14..15: Roll rate * 10 (deg/s * 10)
    int16_t  gyro_y_dps_x10;     // Offset 16..17: Pitch rate * 10 (deg/s * 10)
    int16_t  gyro_z_dps_x10;     // Offset 18..19: Yaw rate * 10 (deg/s * 10)
    uint16_t engine_rpm;         // Offset 20..21: RPM (0 - 25000)
    uint8_t  vehicle_speed_kmh;  // Offset 22:     Speed (0 - 255 km/h)
    uint8_t  throttle_pos_pct;   // Offset 23:     Throttle (0 - 100 %)
    int8_t   coolant_temp_c;     // Offset 24:     Engine coolant temp (-40 .. +127 C)
    int8_t   gear;               // Offset 25:     Calculated gear (-1 = unknown, 0 = N, 1..6)
    uint16_t battery_mv;         // Offset 26..27: Battery voltage (e.g. 14250 = 14.25 V)
    uint8_t  status_flags;       // Offset 28:     Bit 0: SD, Bit 1: Engine run, Bit 2: Countdown, Bit 3: IMU ok, Bit 4: Diag mode
};
```

### Commands (Phone -> ESP32 on `19B10002-...`)
- `0x01`: **Zero-Tare Calibration** (tare roll and pitch to 0.0°).
- `0x02`: **Tare Mounting Roll Offset** (payload: `int16_t offset_x10`, stored in NVS).
- `0x03`: **Configure CAN Signal** (payload: signal index + `CanSignalConfig` struct).
- `0x04`: **Configure CAN Mode / Baudrate** (payload: mode active + baudrate 250/500/1000 kbps).
- `0x20`: **Sync Check** (query un-synced MicroSD log sessions).
- `0x21`: **Sync Request File** (download chunked CSV session from MicroSD).
- `0x22`: **Sync Acknowledge** (mark session file as synced in NVS).
- `0x30`: **Diagnostics Mode** (payload: `1 = Active OBD-II TX`, `0 = Listen-Only RX`).
- `0x31`: **Query DTCs** (triggers OBD-II Mode 03 & 07 fault code read).
- `0x32`: **Clear DTCs** (triggers OBD-II Mode 04 fault code clear).
- `0x40`: **CAN Sniffer Mode** (payload: `1 = Enable raw CAN broadcast`, `0 = Disable`).
- `0x50`: **OTA Update Mode** (payload: `1 = Enable Wi-Fi SoftAP at 192.168.4.1`, `0 = Disable`).

### Responses (ESP32 -> Phone on `19B10002-...`)
- `0xA0`: **Sync Check Response** (session count + file list).
- `0xA1`: **Sync Chunk** (file data transfer block).
- `0xA2`: **Sync ACK Response**.
- `0xB0`: **Diagnostics Mode State** (`[0xB0, active]`).
- `0xB1`: **DTC List** (`[0xB1, count, dtc_entries...]`).
- `0xB2`: **Clear DTC Acknowledged**.
- `0xC0`: **Raw CAN Frame** (`[0xC0, can_id(4), dlc(1), data(8)]`).
- `0xD0`: **OTA Status** (`[0xD0, state(1), ip(4)]`).

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
cd firmware
pio run
pio run --target upload
pio device monitor
```

---

## License
Open-source under MIT License.
