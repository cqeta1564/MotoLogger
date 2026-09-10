# MotoLogger: Project Architecture, Technical Specifications & Context (PROJECT.md)

This document contains the complete, authoritative system specifications, architectural context, hardware definitions, firmware design, mobile application structure, and historical design decisions for **MotoLogger**.

---

## 1. Executive Summary & Vision

### 1.1 What is MotoLogger?
**MotoLogger** is an open, high-frequency, end-to-end motorcycle telemetry and data acquisition ecosystem. It bridges the gap between expensive commercial track data loggers (AIM Solo 2 DL, 2D Datarecording, Starlane) and inaccurate smartphone-only apps.

The system is composed of three interconnected tiers:
1. **MotoLogger Hardware (ESP32-S3):** A ruggedized onboard logger installed directly on the motorcycle, powered from the 12V OBD-II port, logging CAN bus traffic and IMU motion data.
2. **Real-time Dual-Core Firmware (C++ / PlatformIO):** Runs non-blocking FreeRTOS tasks to achieve 100 Hz sensor fusion, 500 kbps TWAI CAN bus capture, 32 KB buffered MicroSD blackbox logging, and a 25 Hz low-latency binary BLE telemetry stream.
3. **Companion Mobile App & Head Unit Projection (Flutter):** An Apple Design System mobile app running on iOS/Android, featuring real-time lean & G-force gauges, offline SQLite storage, MoTeC i2 CSV export, smart fuel-tank calibration, and **Android Auto / Apple CarPlay** dashboard projection.

### 1.2 Why was it built?
- **Vibration & OIS Protection:** Mounting modern smartphones on motorcycle handlebars quickly destroys their optical image stabilization (OIS) magnets and sensors due to high-frequency engine harmonics. MotoLogger keeps the sensitive IMU mounted inside the bike and streams data wirelessly to the phone in the rider's pocket or tank bag.
- **True Lean Angle Accuracy:** Phone-based tilt sensors cannot distinguish between motorcycle lean angle and lateral centrifugal force during cornering. MotoLogger uses the **CEVA/Hillcrest BNO085 9-DoF IMU** with 100 Hz Game Rotation Vector sensor fusion to isolate roll and pitch independently of lateral Gs.
- **Automotive CAN Bus Integration:** Direct capture of engine RPM, vehicle speed, throttle position, coolant temperature, and gear position directly from the ECU via the TWAI CAN bus.
- **Zero-Cloud, 100% Privacy & Offline:** No accounts, no subscriptions, no cloud servers required. Sessions are stored in local SQLite databases and can be exported directly to standard analysis tools (MoTeC i2, RaceRender, TrackAddict).
- **True 0 mA Parasitic Drain:** A hardware power latch automatically cuts all power to the board 15 seconds after the motorcycle engine stops, completely preventing battery drain.

---

## 2. System Architecture & Data Flow

```
                                +-----------------------------+
                                | Motorcycle 12V Battery / OBD |
                                +--------------+--------------+
                                               | 12V & CAN_H / CAN_L
                                               v
    +------------------------------------------------------------------------------------------+
    |                               MotoLogger Hardware (ESP32-S3)                             |
    |                                                                                          |
    |  +--------------------+   +-----------------------+   +-------------------------------+  |
    |  | Power Management   |   | Texas Instruments     |   | CEVA BNO085 9-DoF IMU         |  |
    |  | - FORCE_ON Latch   |   | SN65HVD230 Transceiver|   | - 100 Hz Game Rotation Vector |  |
    |  | - SENSE_V_DIG / ANA|   | - TWAI 500 kbps       |   | - Lean Angle & Pitch Fusion   |  |
    |  | - 15s Auto-Shutdown|   | - Listen-Only & OBD   |   | - Permanent NVS Roll Offset   |  |
    |  +--------------------+   +-----------------------+   +-------------------------------+  |
    |                                      |                               |                   |
    |                                      +---------------+---------------+                   |
    |                                                      |                                   |
    |                                                      v                                   |
    |                                   +-------------------------------------+                |
    |                                   | SPI MicroSD Slot (32 KB Block Write)|                |
    |                                   | Blackbox CSV Logging (LOG_XXXX.CSV) |                |
    |                                   +-------------------------------------+                |
    |                                                      |                                   |
    |                                                      v 25 Hz Binary BLE Stream (28 bytes)|
    +------------------------------------------------------+-----------------------------------+
                                                           |
                                                           v
    +------------------------------------------------------------------------------------------+
    |                               Companion Mobile App (Flutter)                             |
    |                                                                                          |
    |  - High-precision Smartphone GPS Fusion (10 Hz, speed, bearing, altitude)                |
    |  - 100% Offline SQLite Session Store (Sessions, Laps, Track Records)                     |
    |  - MoTeC i2 / CSV / GPX Export Engine                                                    |
    |                                                                                          |
    |   +---------------------------------------+    +-------------------------------------+   |
    |   |           Phone Screen UI             |    |     Head Unit Projection Display    |   |
    |   |  - Dynamic Lean Arc (-60° .. +60°)    |    |  - Android Auto (CarAppService)     |   |
    |   |  - 1.5G G-G Friction Circle           |    |  - Motorcycle TFT (Chigee, Carpuride|   |
    |   |  - Tachometer & Shift Light           |    |  - Large Glanceable Lean & Gear     |   |
    |   |  - Smart Fuel-Tank Calibration Screen |    |  - Auto Screen Lock during Riding   |   |
    |   +---------------------------------------+    +-------------------------------------+   |
    +------------------------------------------------------------------------------------------+
```

---

## 3. Hardware Specifications & Manufacturing

### 3.1 Base Design
- **Architecture:** Based on Magnus Thomé's open-source **RejsaCAN-ESP32-S3** design (v3.4 revision).
- **MCU:** Espressif **ESP32-S3-WROOM-1** (Dual-core Xtensa LX7 @ 240 MHz, 512 KB SRAM, 8 MB Flash, integrated 2.4 GHz Wi-Fi & BLE 5.0).
- **Silkscreen & Branding:** Cleaned and customized with neutral silkscreen (no third-party branding), manufactured via JLCPCB SMT assembly.
- **PCB Manufacturing Files:** Stored under [`hardware/`](./hardware/):
  - `hardware/gerbers/MotoLogger_Clean_Gerber.zip` (Main board)
  - `hardware/gerbers/MotoLogger_OBD2_Plug_Gerber.zip` (OBD-II sandwich adapter)
  - `hardware/assembly/MotoLogger_BOM.csv` & `.xlsx` (LCSC part numbers)
  - `hardware/assembly/MotoLogger_Part_Placements.zip` (Centroid / CPL data)

### 3.2 Pin Mapping Table

| Function | GPIO Pin | Signal Name | Description |
| :--- | :--- | :--- | :--- |
| **CAN Bus TX** | `GPIO14` | `CAN_TX` | SN65HVD230 Transceiver TX |
| **CAN Bus RX** | `GPIO13` | `CAN_RX` | SN65HVD230 Transceiver RX |
| **CAN Mode Control** | `GPIO38` | `CAN_RS` | Transceiver Mode (LOW = 500k Active, HIGH = Standby) |
| **IMU I2C Data** | `GPIO1` | `SDA` | BNO085 Native I2C Data (400 kHz) |
| **IMU I2C Clock** | `GPIO2` | `SCL` | BNO085 Native I2C Clock |
| **IMU Interrupt** | `GPIO12` | `H_INTN` | BNO085 Data-Ready Interrupt (Active LOW) |
| **IMU Reset** | `GPIO48` | `RST` | BNO085 Hardware Reset (Active LOW) |
| **Switched 3.3V Rail** | `GPIO21` | `HI_DRIVER` / `3V3_SWITCH` | MT9700 High-side load switch powering IMU & peripherals |
| **MicroSD SPI CS** | `GPIO45` | `SD_CARD` | MicroSD Chip Select |
| **MicroSD SPI SCK** | `GPIO39` | `CLK` | SPI Clock (25 MHz) |
| **MicroSD SPI MOSI**| `GPIO40` | `MOSI` | SPI Master Out Slave In |
| **MicroSD SPI MISO**| `GPIO41` | `MISO` | SPI Master In Slave Out |
| **Power Latch** | `GPIO17` | `FORCE_ON` | Keep HIGH to maintain 12V power latch; LOW = 0 mA shutdown |
| **Digital Battery Sense**| `GPIO8` | `SENSE_V_DIG` | Optocoupler/transistor sense (HIGH when engine runs) |
| **Analog Battery Sense** | `GPIO9` | `SENSE_V_ANA` | ADC with 1:11 resistor divider (measures 0–16V battery) |
| **Blue Status LED** | `GPIO10` | `BLUE_LED` | IMU / MicroSD status / Auto-shutdown countdown |
| **Yellow Status LED** | `GPIO11` | `YELLOW_LED`| 3.3V power rail status / CAN frame burst flash |

### 3.3 Power Management & Automotive Protection
- Direct 12V input from motorcycle battery via OBD-II pin 16.
- High-efficiency buck regulator step-down to 3.3V.
- Reverse polarity and transient overvoltage protection (automotive TVS diodes).
- **Auto-Shutdown Logic:**
  - When the engine runs, the alternator generates ~14.2V. `SENSE_V_DIG` (`GPIO8`) goes HIGH and `SENSE_V_ANA` (`GPIO9`) reads > 13.2V.
  - When ignition is switched off, battery voltage drops below ~12.8V.
  - The firmware initiates a 15-second grace countdown (indicated by blinking `BLUE_LED`).
  - If the engine does not restart within 15 seconds, all files on the MicroSD are flushed and closed, and `FORCE_ON` (`GPIO17`) is driven LOW.
  - The board powers off completely with **0 mA quiescent drain**, eliminating any chance of draining the motorcycle battery during winter storage.

---

## 4. Firmware Architecture (`firmware/`)

### 4.1 Technology & Framework
- Platform: **PlatformIO** with Arduino-ESP32 framework (`platformio.ini`).
- Target: `esp32-s3-devkitc-1`, 240 MHz, C++17.
- External Libraries: `NimBLE-Arduino` (lightweight BLE stack), `Adafruit_BNO08x` / `sh2` (BNO085 IMU driver), `Preferences` (NVS flash storage), `SD` & `SPI`.

### 4.2 Dual-Core FreeRTOS Task Distribution
To prevent sensor fusion jitter and avoid dropping CAN frames, tasks are strictly pinned to dedicated cores:

| Task Name | Core | Priority | Stack Size | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `Task_CAN` | **Core 0** | 5 (High) | 4 KB | Non-blocking TWAI receiver; parses broadcast CAN & OBD PIDs |
| `Task_BLE` | **Core 0** | 3 (Normal) | 4 KB | Broadcasts 28-byte telemetry packet at 25 Hz to smartphone |
| `Task_Supervisor`| **Core 0** | 2 (Low) | 3 KB | Battery voltage monitor, shutdown countdown, LED patterns |
| `Task_IMU` | **Core 1** | 4 (High) | 4 KB | Reads BNO085 at 100 Hz, applies roll offset, calculates lean/pitch |
| `Task_Storage` | **Core 1** | 3 (Normal) | 6 KB | Reads from telemetry ring buffer, writes 32 KB blocks to MicroSD |

### 4.3 Sensor Fusion & Vibration Rejection
Motorcycles generate violent high-frequency vibrations from 1-cylinder to 4-cylinder combustion engines. Standard accelerometers and complementary filters fail, causing massive tilt errors.
- MotoLogger uses the Hillcrest **BNO085 32-bit ARM Cortex-M0+ coprocessor** running the **Game Rotation Vector (GRV)** report.
- **Why Game Rotation Vector?** GRV fuses gyroscopes and accelerometers without using the magnetometer. Motorbikes have strong, rapidly changing electromagnetic fields generated by the alternator, ignition coils, and steel frames that distort magnetometers. GRV provides rock-solid, drift-free roll and pitch angles up to 100 Hz.

### 4.4 Roll Offset Calibration & NVS Storage
The hardware board may be installed inside the bike at a slight roll offset relative to the motorcycle's frame:
$$\theta_{\text{corrected}} = \theta_{\text{raw}} - \theta_{\text{offset}}$$
- In firmware (`imu_manager.cpp`), the roll offset \(\theta_{\text{offset}}\) is stored permanently in the ESP32 non-volatile storage (NVS) using the `Preferences` library (namespace: `motologger`, key: `roll_offset`).
- On boot, `ImuManager::begin()` loads the stored offset.
- When the smartphone sends a calibration command, `setRollOffset(deg)` immediately updates the live offset and writes it to NVS.

### 4.5 BLE GATT Protocol & Packet Specification
The BLE server uses **NimBLE** with high transmit power (+9 dBm) to guarantee a reliable connection through the rider's jacket or tank bag.

- **BLE Device Name:** `MotoLogger-ESP32`
- **Telemetry Service UUID:** `180D` (or custom 128-bit)
- **Telemetry Characteristic (Notify, Read):** 28-byte packed binary struct (`BleTelemetryPacket`):

```cpp
struct __attribute__((packed)) BleTelemetryPacket {
    uint32_t timestamp_ms;       // Monotonic timestamp in milliseconds
    int16_t  lean_angle_x10;     // Roll * 10 (-1800 .. +1800 -> +/- 180.0 deg)
    int16_t  pitch_x10;          // Pitch * 10 (-900 .. +900 -> +/- 90.0 deg)
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
    uint8_t  status_flags;       // Bit 0: SD active, Bit 1: Engine run, Bit 2: Countdown, Bit 3: IMU ok
};
```
*Advantage:* Zero JSON overhead, zero string parsing, exactly 28 bytes unpacked directly via Dart `ByteData` in microseconds.

- **Command Characteristic (Write, WriteNR):**
  - `0x01`: Instant Zero-Tare (taring current position to 0.0°).
  - `0x02`: Calibrate Tare Mounting Offset (`payload: int16_t offset_x10` in tenths of a degree, little-endian).

---

## 5. Mobile Companion App (`app/`)

### 5.1 Technology Stack & Architecture
- Framework: **Flutter 3.x** / Dart 3.x (Multiplatform Android & iOS).
- Key Plugins:
  - `flutter_blue_plus`: Bluetooth Low Energy connection and background streaming.
  - `sqflite`: High-speed local SQLite database for session and sample storage.
  - `geolocator`: Smartphone GPS fusion (coordinates, speed, heading, altitude).
  - `share_plus`: File sharing for exported CSV and GPX files.
- Directory Structure:
  - `lib/core/`: Apple Design System theme (`AppTheme`), formatting utilities, constants.
  - `lib/models/`: `TelemetrySample`, `Session`, `CalibrationSettings`.
  - `lib/services/`: `BleService`, `TelemetryManager`, `DatabaseService`, `GpsService`.
  - `lib/ui/dashboard/`: Main telemetry dashboard, lean gauge, friction circle, tachometer.
  - `lib/ui/settings/`: `TankCalibrationScreen`, device connection, logger settings.
  - `lib/ui/sessions/`: Session history, lap browser, CSV/GPX export.
  - `lib/ui/widgets/`: `ConstructionSpiritLevel`, `PhonePlacementAnimation`, `BikeUprightAnimation`.

### 5.2 The Smart Fuel-Tank Calibration System
Motorcyclists rarely carry bubble levels or paddock stands with them. MotoLogger features a calibration mechanism:

#### The Concept:
1. Every motorcycle fuel tank filler cap is engineered to be flat and level with the motorcycle chassis centerline.
2. When the motorcycle is parked on its side stand, it leans at a fixed angle (typically 10° to 18° depending on bike model and suspension setup).
3. The smartphone's internal accelerometer already knows true gravitational down to 0.1° accuracy.
4. **Procedure:**
   - The rider parks the bike on its side stand.
   - Places the smartphone flat on the circular fuel tank filler cap.
   - The phone measures the exact side-stand lean angle: $\theta_{\text{tank}}$.
   - Simultaneously, the ESP32-S3 logger (mounted inside the bike) measures its own roll angle: $\theta_{\text{esp}}$.
   - The mounting offset of the logger is:
     $$\theta_{\text{offset}} = \theta_{\text{esp}} - \theta_{\text{tank}}$$
   - The app sends this offset to the ESP32 via BLE command `0x02`.
   - The ESP32 saves the offset permanently in NVS flash.
   - From that moment on, whenever the bike is upright, the logger outputs exactly **0.0°**.

#### Upright Alternative:
- For riders using a paddock stand or holding the bike upright, the app provides a second tab: **"Svisle (na stojanu)"**.
- In this mode, the offset is calibrated directly against 0.0°.

#### UI & Visual Metaphors:
- **`PhonePlacementAnimation`:** A line-art silhouette of the motorcycle resting on its side stand, showing a smartphone descending smoothly onto the fuel tank lid with subtle contact waves.
- **`ConstructionSpiritLevel`:** A yellow workshop spirit level (classic 40cm builder's level with fluid, glass vial, and air bubble). Provides intuitive physical feedback with witty Czech states:
  - *"Křivý jak šavle"* (Tilted)
  - *"Ustálit..."* (Settling)
  - *"V lajně / Na milimetr přesně!"* (Leveled)

### 5.3 Apple Design System & Ergonomics
- **Light Theme Only:** Pure `#F2F2F7` background, `#FFFFFF` cards, `#1C1C1E` typography.
- **No AI Aesthetic:** No fake neon glow, no robotic gradients, no generic AI greeting text.
- **Button Uniformity:** All action and confirmation buttons share identical height (`54 px`), border radius (`14 px`), and aligned vertical bottom margins across screens.
- **Automatic Screen Locking:** The screen automatically locks when vehicle speed exceeds 5 km/h, preventing accidental touches from raindrops, wind, or gloves.

### 5.4 Android Auto & CarPlay Head Unit Projection
- Android Auto integration via Android `CarAppService` (`android/` configuration).
- Allows projecting high-contrast, glanceable telemetry (current lean angle, maximum left/right lean, gear indicator, shift light) directly onto motorcycle TFT displays supporting Android Auto / CarPlay (e.g. Chigee AIO-5, Carpuride W502/W702, Ottocast).

---

## 6. Monorepo Structure

```
MotoLogger/
├── AGENTS.md                                # AI Agent rules, guidelines, and conventions
├── GEMINI.md                                # Antigravity project configuration & rules
├── PROJECT.md                               # Complete system architecture and documentation
├── README.md                                # Public repository overview and quickstart
│
├── hardware/                                # Production PCB manufacturing & assembly data
│   ├── gerbers/                             # Cleaned Gerber ZIP files (neutral silkscreen)
│   ├── assembly/                            # BOM (CSV/XLSX) and Part Placement files
│   └── schematics/                          # Circuit diagrams, JSON source, pinout headers
│
├── firmware/                                # Modular C++ ESP32-S3 Firmware (PlatformIO)
│   ├── platformio.ini                       # Build environment and dependencies
│   ├── include/                             # Header files (config.h, types.h, ring_buffer.h)
│   └── src/                                 # Drivers (can, imu, ble, power, storage, main)
│
└── app/                                     # Companion Flutter Mobile App
    ├── pubspec.yaml                         # Flutter dependencies
    ├── lib/                                 # Dart source code (Clean Architecture)
    ├── android/                             # Android configuration + Android Auto Service
    └── test/                                # Automated unit test suite (tank calibration, etc.)
```

---

## 7. Verification & Quality Assurance

### 7.1 Mobile App Validation
```bash
# In MotoLogger/app:
flutter analyze   # Must pass with 0 errors and 0 warnings
flutter test      # Must pass 100% of unit tests
```

### 7.2 Firmware Compilation
```bash
# In MotoLogger/firmware:
pio run           # Compiles for ESP32-S3 with 0 compilation errors
```

---

## 8. Development Roadmap & Future Enhancements

1. **GPS Track Lap Timer:** Implement automatic track detection, finish line crossing detection via GPS coordinates, and sector split times directly in the mobile app.
2. **Extended OBD-II PID Interrogation:** Configurable PID polling engine for specific motorcycle models (Ducati, BMW, Yamaha, KTM) to extract lean ABS intervention, traction control status, and throttle grip vs. butterfly valve angles.
3. **P2P Session Sharing:** Direct Wi-Fi / BLE session transfer between riders without internet connectivity.
