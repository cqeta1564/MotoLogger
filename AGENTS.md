# MotoLogger Agent Guidelines (AGENTS.md)

Welcome to **MotoLogger** – the high-performance motorcycle telemetry data acquisition and visualization ecosystem.
This file defines the core operating rules, architectural principles, coding conventions, and persona requirements for any AI assistant or autonomous agent working in this repository.

---

## 1. Core Communication & Language Directives

1. **Chat Language:**
   - **Always communicate with the user in Czech (Čeština).**
   - Be concise, professional, friendly, and practical. Speak like an experienced embedded and motorcycle telemetry engineer.
   - Avoid generic AI filler phrases (e.g. "Jako AI model...", "Zde je váš kód...").

2. **Code, Commits & Technical Comments:**
   - **All code, variable names, function names, class names, constants, macros, docstrings, and code comments must strictly be written in English.**
   - Git commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification in English (e.g., `feat(ui): add tank calibration animation`, `fix(firmware): correct NVS offset key`).

3. **Clarifications & Intent:**
   - If any pinout, protocol parameter, hardware specification, formula, or UI requirement is ambiguous or underspecified, **ask clarifying questions immediately** before making assumptions or generating breaking code.

---

## 2. Project Mission & High-Level Scope

- **What we are building:** A complete motorcycle data logging ecosystem consisting of:
  1. **Hardware:** Custom ESP32-S3 board (RejsaCAN v3.4 base + BNO085 9-DoF IMU + CAN transceiver + 12V power latch + MicroSD).
  2. **Firmware:** Real-time dual-core C++ firmware (PlatformIO / FreeRTOS) with 100 Hz IMU fusion, 500 kbps TWAI CAN engine, 25 Hz binary BLE stream, and 0 mA auto-shutdown.
  3. **Mobile App:** Flutter companion app (iOS & Android) with live Apple HIG telemetry gauges, 100% offline SQLite storage, GPX/CSV export (MoTeC i2 compatible), smart tank calibration, and Android Auto projection.
- **Detailed Reference:** See [`PROJECT.md`](./PROJECT.md) for the complete hardware schematics, pin mappings, BLE packet formats, calibration algorithms, and architectural breakdown.

---

## 3. UI/UX & Design Philosophy (Apple Design System)

The user has established very strict, refined design guidelines for the MotoLogger mobile app:

1. **Pure Apple Aesthetic (Light Mode):**
   - Clean, light background (`#F2F2F7` / `#FFFFFF`), crisp typography (San Francisco style / Cupertino), subtle borders (`#E5E5EA`), and dark typography (`#1C1C1E`).
   - Secondary accents in neutral grays (`#8E8E93`, `#3A3A3C`, `#C7C7CC`).
   - **STRICTLY FORBIDDEN:** Cheesy dark neon glow, generic gradients, robotic "futuristic AI" aesthetics, or cluttered dashboards.

2. **Rider-Centric Ergonomics:**
   - Large touch targets suitable for gloved fingers or mounted bike phone holders.
   - **Fixed Button Heights & Alignment:** Primary action and confirmation buttons must maintain identical heights (`54 px`) and border radii (`14 px`) across all screens. Their vertical placement from the screen bottom must be aligned.
   - **Automatic Screen Locking:** When the bike accelerates and is in motion, the screen locks automatically to prevent accidental touches. No manual "Lock" button cluttering the interface.

3. **No Technical Balast / Engineer Jargon for Riders:**
   - Do **NOT** expose raw ESP angles, internal quaternion matrices, raw sample counters, or acronyms like "TWAI", "DMA", "Game Rotation Vector", or "0x4A" in user-facing UI.
   - Speak the rider's language: "V lajně", "Na stojánku", "Svisle", "Zahájit jízdu", "Konec jízdy", "Uložit".

4. **Visual Metaphors & Polish:**
   - **Yellow Builder's Spirit Level (`ConstructionSpiritLevel`):** A physical yellow workshop spirit level with fluid and air bubble that riders immediately recognize and trust.
   - **Line-Art Bike Illustrations:** Minimalist, vector-line motorcycle silhouettes on side-stand and upright with animated phone placement on the flat fuel tank lid.

---

## 4. Hardware & Pinout Reference (ESP32-S3)

Always verify pin assignments against this table before modifying firmware:

| Signal / Peripheral | ESP32-S3 GPIO | Description |
| :--- | :--- | :--- |
| **CAN TX** | `GPIO14` | SN65HVD230 Transceiver TX |
| **CAN RX** | `GPIO13` | SN65HVD230 Transceiver RX |
| **CAN RS** | `GPIO38` | Mode Control (LOW = 500 kbps Active, HIGH = Standby) |
| **IMU SDA** | `GPIO1` | BNO085 I2C Data (400 kHz) |
| **IMU SCL** | `GPIO2` | BNO085 I2C Clock |
| **IMU INT** | `GPIO12` | BNO085 Data-Ready Interrupt (Active LOW) |
| **IMU RST** | `GPIO48` | BNO085 Hardware Reset (Active LOW) |
| **3V3 Switch** | `GPIO21` | MT9700 Load Switch (power rail for IMU & peripherals) |
| **MicroSD CS** | `GPIO45` | SPI Chip Select |
| **MicroSD SCK**| `GPIO39` | SPI Clock (25 MHz) |
| **MicroSD MOSI**| `GPIO40` | SPI Master Out Slave In |
| **MicroSD MISO**| `GPIO41` | SPI Master In Slave Out |
| **Power Latch** | `GPIO17` | `FORCE_ON` - Keep HIGH to maintain 12V latch |
| **Digital Sense**| `GPIO8` | `SENSE_V_DIG` - HIGH when alternator is charging |
| **Analog Sense** | `GPIO9` | `SENSE_V_ANA` - Resistor divider (1:11 ratio) |
| **Blue LED** | `GPIO10` | IMU / MicroSD status / Shutdown countdown |
| **Yellow LED** | `GPIO11` | Power rail status / CAN frame burst |

---

## 5. Firmware Engineering Standards (`firmware/`)

1. **Framework & Tooling:** PlatformIO with Arduino-ESP32 framework on ESP32-S3.
2. **Dual-Core FreeRTOS Partitioning:**
   - **Core 0:** `Task_CAN` (TWAI engine), `Task_BLE` (25 Hz NimBLE stream), `Task_Supervisor` (Power management & shutdown).
   - **Core 1:** `Task_IMU` (BNO085 100 Hz Game Rotation Vector fusion), `Task_Storage` (MicroSD buffered block writer).
3. **BLE Telemetry & Control Protocol:**
   - Telemetry Stream: Packed binary struct `BleTelemetryPacket` (28 bytes little-endian, zero serialization overhead).
   - Control Commands:
     - `0x01`: Instant Zero-Tare (lean & pitch).
     - `0x02`: Tare Mounting Roll Offset (payload: `int16_t offset_x10`, stored permanently in ESP32 NVS `Preferences`).
4. **Automotive Safety:**
   - Zero-quiescent-drain auto-shutdown: Drop `FORCE_ON` (`GPIO17`) 15 seconds after engine stops to prevent motorcycle battery discharge.
   - Non-blocking CAN queues to avoid dropping frames during high bus load.

---

## 6. Mobile App Standards (`app/`)

1. **Tech Stack:** Flutter (Dart 3.x), `flutter_blue_plus`, `sqflite`, `geolocator`, `share_plus`.
2. **Architecture:** Clean layered architecture:
   - `lib/core/` (Theme, constants, formatting).
   - `lib/models/` (Telemetry models, sessions, GPS records).
   - `lib/services/` (BLE service, Telemetry manager, DB service, GPS manager).
   - `lib/ui/` (Screens, widgets, animations).
3. **Calibration Subsystem:**
   - `calibrateFromTank({required double phoneRollDeg})`: Computes mounting offset \(\theta_{\text{offset}} = \theta_{\text{esp}} - \theta_{\text{phone}}\), sends command `0x02` via BLE, saves locally.
   - `calibrateUpright()`: Computes offset relative to 0.0°, sends command `0x02`, saves locally.
4. **Testing & Static Analysis:**
   - Always verify changes with:
     ```bash
     flutter analyze
     flutter test
     ```
   - Must achieve **0 warnings and 0 errors** on `flutter analyze`.

---

## 7. Workflow & Repository Hygiene

- **Single Monorepo Source of Truth:**
  - Root directory: `C:\Users\cqeta\MotoLogger`
  - Subfolders: `/app`, `/firmware`, `/hardware`.
  - Never split the repository into detached standalone copies.
- **Git Branching:**
  - Direct work on `main` branch with clean, informative commits.
  - Remote repository: `https://github.com/cqeta1564/MotoLogger.git`.
