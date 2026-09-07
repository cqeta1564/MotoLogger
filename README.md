# MotoLogger: Comprehensive Motorcycle Telemetry Ecosystem

[![PlatformIO](https://img.shields.io/badge/Firmware-ESP32--S3_PlatformIO-orange.svg)](https://platformio.org/)
[![Flutter](https://img.shields.io/badge/App-Flutter_Android_&_iOS-blue.svg)](https://flutter.dev/)
[![Android Auto](https://img.shields.io/badge/Projection-Android_Auto_&_CarPlay-green.svg)](https://developer.android.com/training/cars/apps)
[![Hardware](https://img.shields.io/badge/Hardware-MotoLogger_v3.4-red.svg)](hardware/)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

An end-to-end, high-performance motorcycle telemetry and data acquisition system. Features a custom **ESP32-S3 hardware logger**, **100 Hz BNO085 IMU fusion** for vibration-resistant lean angle calculation, **500 kbps TWAI CAN bus capture**, and a companion **Flutter mobile app** with **Android Auto** and **Apple CarPlay** dashboard projection. 100% offline and serverless.

---

## System Architecture

```
                                    +-----------------------------+
                                    | Motorcycle 12V Battery / OBD |
                                    +--------------+--------------+
                                                   | Power & CAN
                                                   v
   +-----------------------------------------------------------------------------------------------+
   |                                  MotoLogger Hardware (ESP32-S3)                               |
   |                                                                                               |
   |   [CAN Transceiver]  <--->  TWAI 500 kbps Engine (Listen-Only + Active OBD-II PIDs)           |
   |   [BNO085 9-DoF IMU] <--->  100 Hz Game Rotation Vector (Lean Angle / Roll & Pitch Fusion)     |
   |   [Power Latch]      <--->  Automatic 12V Latch & 15s Auto-Shutdown (0 mA Quiescent Drain)    |
   |   [MicroSD Slot]     <--->  32 KB Buffered Lossless Blackbox Logging (LOG_XXXX.CSV)           |
   +-----------------------------------------------+-----------------------------------------------+
                                                   |
                                                   | 25 Hz Real-Time BLE Stream (28-byte packet)
                                                   | (Coexists with wireless CarPlay / Android Auto)
                                                   v
   +-----------------------------------------------------------------------------------------------+
   |                                MotoLogger Mobile App (Flutter)                                |
   |                                                                                               |
   |   - Real-time Smartphone GPS Fusion (Coordinates, Bearing, Altitude, Speed)                    |
   |   - 100% Offline Local SQLite Storage (Sessions & Track Records)                              |
   |   - Export to CSV (MoTeC i2 / RaceRender / TrackAddict) and GPX                               |
   |                                                                                               |
   |       +------------------------------------+    +------------------------------------+        |
   |       |          Phone Screen UI           |    |     Head Unit Display Projection   |        |
   |       |  - Dynamic Lean Gauge (-60°..+60°) |    |  - Android Auto (Motorcycle TFT)   |        |
   |       |  - 1.5G G-G Friction Circle        |    |  - Apple CarPlay                   |        |
   |       |  - RPM Tachometer & Shift Light    |    |  - Large Gear & Lean Readout       |        |
   |       |  - Gear Indicator (N, 1..6)        |    |  - Remote One-Touch Zero-Tare      |        |
   |       +------------------------------------+    +------------------------------------+        |
   +-----------------------------------------------------------------------------------------------+
```

---

## Repository Structure

```
MotoLogger/
├── hardware/                                # Complete PCB manufacturing & assembly files
│   ├── gerbers/                             # Production Gerber ZIP archives (neutral silkscreen)
│   │   ├── MotoLogger_v3.4_Clean_Gerber.zip # Main board gerbers
│   │   └── MotoLogger_OBD2_Plug_Gerber.zip  # OBD-II sandwich board gerbers
│   ├── assembly/                            # SMT / PCBA manufacturing data
│   │   ├── MotoLogger_v3.4_BOM.csv          # Bill of Materials with LCSC part numbers
│   │   ├── MotoLogger_v3.4_BOM.xlsx         # Formatted Excel BOM
│   │   ├── MotoLogger_v3.4_Part_Placements.zip # Top and bottom SMT placement diagrams
│   │   └── Ordering_Specs_JLCPCB_PCBWay.md  # Detailed fabrication and assembly specs
│   └── schematics/                          # Circuit schematics and reference
│       ├── MotoLogger_v3.4_Schematic.png    # Circuit schematic diagram
│       ├── MotoLogger_v3.4_Schematic.json   # Schematic source
│       └── MotoLogger_Pinout_Reference.h    # Header pad mapping reference
│
├── firmware/                                # Modular C++ ESP32-S3 Firmware (PlatformIO)
│   ├── platformio.ini                       # PlatformIO build configuration
│   ├── include/                             # Header definitions (config.h, types.h, ring_buffer.h)
│   └── src/                                 # Subsystem implementations (CAN, IMU, BLE, Power, Storage)
│
└── app/                                     # Companion Mobile App (Flutter)
    ├── pubspec.yaml                         # Flutter dependencies
    ├── lib/                                 # Dart source code (UI, BLE, GPS, SQLite, Models)
    └── android/                             # Android configuration + Android Auto Service
```

---

## Hardware Specifications & Pinout

| Periphery / Function | ESP32-S3 Pin | Signal Description |
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
| **Digital Battery Sense**| `GPIO8` | `SENSE_V_DIG` - HIGH when alternator is charging |
| **Analog Battery Sense** | `GPIO9` | `SENSE_V_ANA` - ADC with 1:11 resistor divider |
| **Blue LED** | `GPIO10` | IMU / MicroSD status / Auto-shutdown countdown |
| **Yellow LED** | `GPIO11` | Power rail status / CAN frame burst flash |

---

## Quick Start Guide

### 1. Firmware Build & Upload (PlatformIO)
```bash
# Navigate to firmware directory
cd firmware

# Build firmware
pio run

# Flash to connected ESP32-S3 over USB-C
pio run --target upload

# Open Serial Monitor (115200 baud)
pio device monitor
```

### 2. Mobile App Run (Flutter)
```bash
# Navigate to mobile app directory
cd app

# Fetch packages
flutter pub get

# Run on connected phone or emulator
flutter run
```

### 3. Android Auto Head Unit Setup
1. In phone **Settings > Android Auto**, tap **Version** 10 times to enable **Developer Mode**.
2. Open top-right menu > **Developer settings**, enable **Unknown sources**.
3. Connect phone to your motorcycle display (e.g. Chigee AIO-5, Carpuride, Ottocast) and open MotoLogger.

---

## License
Open-source under MIT License.
