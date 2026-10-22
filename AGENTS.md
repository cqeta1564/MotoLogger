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

The MotoLogger mobile app follows strict, refined design guidelines based on the Apple Design System and rider ergonomics:

1. **Pure Apple Aesthetic (Light Mode Only):**
   - Canvas: `#F2F2F7`, Card/Content surfaces: `#FFFFFF`, Primary text: `#1C1C1E`, Secondary text: `#63636B`, Borders/Dividers: `#E5E5EA`.
   - Accent: System-style blue (`#0066CC`), strictly restricted to selection and primary actions.
   - Status Bar & Chrome: Always request dark system icons (`SystemUiOverlayStyle.dark`) across all light screens. Never draw fake status bars or Dynamic Islands.
   - **STRICTLY FORBIDDEN:** Tacky dark neon glow, generic gradients, robotic "futuristic AI" aesthetics, or cluttered dashboards.

2. **Liquid Glass Approximation (`GlassSurface`):**
   - `GlassSurface` is a strictly bounded Flutter `BackdropFilter` approximation (local blur, neutral translucent tint, thin border highlight, soft shadow).
   - **Where to use:** Floating navigation capsule (`AppleTabBar`) and floating contextual action panels.
   - **Where NOT to use:** NEVER use per-row in scrollable lists or behind entire screens. Content remains crisp and opaque.
   - **Opaque Fallback ("Omezit průhlednost"):** Respects the persisted `reduce_transparency` SQLite preference (`AppPreferences`), high contrast, and accessibility navigation. Bypasses all `BackdropFilter` shaders and renders solid opaque surfaces with subtle borders.

3. **Sliding Capsule Navigation & Retained State:**
   - **Top-Level Destinations (3 Tabs):** **Jízda** (Ride / Dashboard) → **Historie** (History / Sessions) → **Nastavení** (Settings).
   - **Sliding Capsule Indicator:** `AppleTabBar` animates tab selection with a 260 ms ease-out sliding capsule and interruptible 180 ms content transition (`TabContentTransition`).
   - **Retained State:** Tabs use `IndexedStack` / state preservation to preserve scroll offsets, active ride recording, and search filters across tab switches.
   - **Android Back Navigation:** Pressing Android Back on secondary tabs (History, Settings) always returns to **Jízda** first before exiting the app.

4. **Directional Lean Feedback (`CornerGradientBreather`):**
   - Directional edge wash on screen margins driven by calibrated roll angle (negative roll = left edge, positive roll = right edge).
   - **Visual Angle Bands:** 1° dead zone; ≤ 15° green (cruising); 15°–30° orange (sporty); ≥ 30°–45°+ red (knee-down limit). (Note: visual lean angle guides, not tire grip measurements).
   - Blends telemetry over 100 ms; immediately clears wash upon disconnect or invalid data. Renders a narrow solid edge in reduced-transparency mode. Strictly no perpetual looping pulse.

5. **Motion Policy & Accessibility (`AppMotion`):**
   - Centralized animation controller (`AppMotion`) respecting OS reduced motion (`MediaQuery.disableAnimationsOf(context)` or user preference).
   - Transitions (capsule slide, action panel resize) are bypassed when reduced motion is enabled to prevent layout re-entry bugs.
   - No looping shimmer effects on unlock controls.

6. **Truthful States & Error Resilience:**
   - **No Fabricated Telemetry:** Unavailable sensor or BLE data displays an em-dash (`—`), never a fabricated `0.0°`.
   - **Hardware vs. Demo State:** Explicit "Vyzkoušet demo" action. Demo sessions are stored with `isDemo: true` and labeled "Demo", never masquerading as live hardware.
   - **Ride Persistence Safety:** Ride recording buffers samples in memory during transient SQLite failures, keeps the ride recoverable, and provides an explicit retry button.
   - **Hardware Truthfulness:** Settings do not claim active SD-card logging or encryption without live BLE/service verification. Calibration handles missing phone sensors gracefully.

7. **Rider-Centric Ergonomics & Touch Controls:**
   - **Fixed Button Geometry:** Primary action and confirmation buttons (`PrimaryAction`) must maintain identical heights (`54 px`) and border radii (`14 px`) across all screens.
   - **Minimum Touch Targets:** All interactive controls must be at least 48 logical units.
   - **Automatic Screen Locking:** When vehicle speed exceeds 5 km/h, the screen locks automatically. Unlock is supported via both `SlideToUnlock` and an accessible unlock button.
   - **Rider Language (No Technical Balast):** Do NOT expose raw quaternion matrices, DMA buffers, TWAI registers, or raw sample counters. Speak rider language: "V lajně", "Na stojánku", "Svisle", "Zahájit jízdu", "Konec jízdy", "Uložit".

8. **Visual Metaphors & Polish:**
   - **Yellow Builder's Spirit Level (`ConstructionSpiritLevel`):** Physical yellow workshop spirit level with fluid vial and air bubble with witty Czech states: *"Křivý jak šavle"*, *"Ustálit..."*, *"V lajně / Na milimetr přesně!"*.
   - **Line-Art Bike Illustrations:** Minimalist vector-line silhouettes (`PhonePlacementAnimation`, `BikeUprightAnimation`) for intuitive tank lid and upright calibration.

---

## 4. Hardware & Pinout Reference (ESP32-S3)

Always verify pin assignments against this table before modifying firmware:

| Signal / Peripheral | ESP32-S3 GPIO | Description |
| :--- | :--- | :--- |
| **CAN TX** | `GPIO14` | SN65HVD230 Transceiver TX |
| **CAN RX** | `GPIO13` | SN65HVD230 Transceiver RX |
| **CAN RS** | `GPIO38` | Mode Control (LOW = 500 kbps Active, HIGH = Standby) |
| **IMU MISO** | `GPIO1` | BNO085 SPI MISO (GY-BNO08X `SDA/MISO/TX`) |
| **IMU SCK** | `GPIO2` | BNO085 SPI Clock (3 MHz) (GY-BNO08X `SCL/SCK/RX`) |
| **IMU MOSI** | `GPIO4` | BNO085 SPI MOSI (GY-BNO08X `ADDR/MOSI`; or `GPIO6` on custom PCB breakout pad) |
| **IMU CS** | `GPIO5` | BNO085 SPI Chip Select (Active LOW; or `GPIO47` on custom PCB breakout pad) |
| **IMU INT** | `GPIO12` | BNO085 SHTP Interrupt / Data-Ready (Active LOW) |
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

> *Note on DevKit vs Custom PCB:* DevKitC-1 boards use GPIO4 (MOSI) and GPIO5 (CS). When compiling for the custom RejsaCAN v3.4 PCB with breakout pads, define `-D MOTOLOGGER_PCB_BREAKOUT_PADS` to route MOSI to `GPIO6` and CS to `GPIO47`.

---

## 5. Firmware Engineering Standards (`firmware/`)

1. **Framework & Tooling:** PlatformIO with Arduino-ESP32 framework on ESP32-S3.
2. **Dual-Core FreeRTOS Partitioning:**
   - **Core 0:** `Task_CAN` (TWAI engine), `Task_BLE` (25 Hz NimBLE stream), `Task_Supervisor` (Power management & shutdown).
   - **Core 1:** `Task_IMU` (BNO085 100 Hz Game Rotation Vector fusion), `Task_Storage` (MicroSD buffered block writer).
3. **BLE Telemetry & Control Protocol:**
   - Telemetry Stream: Packed binary struct `BleTelemetryPacket` (29 bytes little-endian: 28 bytes telemetry + 1 byte `status_flags`, zero serialization overhead).
   - Control Commands:
     - `0x01`: Instant Zero-Tare (lean & pitch).
     - `0x02`: Tare Mounting Roll Offset (payload: `int16_t offset_x10`, stored permanently in ESP32 NVS `Preferences`).
4. **Automotive Safety:**
   - Zero-quiescent-drain auto-shutdown: Drop `FORCE_ON` (`GPIO17`) 15 seconds after engine stops to prevent motorcycle battery discharge.
   - Non-blocking CAN queues to avoid dropping frames during high bus load.

---

## 6. Mobile App Standards (`app/`)

1. **Tech Stack:** Flutter (Dart 3.x, min Android API 24), `flutter_blue_plus`, `sqflite`, `geolocator`, `share_plus`.
2. **Architecture & Directory Structure:**
   - `lib/core/`:
     - `theme/app_theme.dart` (Apple light palette, typography, button geometries).
     - `motion/app_motion.dart` (Reduced-motion policy and transition timing constants).
     - `preferences/app_preferences.dart` (SQLite-persisted settings like `reduce_transparency`).
   - `lib/models/`: `telemetry_sample.dart`, `session.dart`, `bike_profile.dart`, `can_definition.dart`, `gps_record.dart`.
   - `lib/services/`: `ble_service.dart`, `telemetry_manager.dart`, `database_service.dart`, `gps_service.dart`, `can_profile_service.dart`.
   - `lib/ui/dashboard/`: `dashboard_screen.dart` (Ride HUD, lean gauges, tachometer, lock overlay, action controls).
   - `lib/ui/history/`: `history_screen.dart`, `session_detail_screen.dart` (Season summary, session search/sort/selection, GPS track map, G-G diagram, MoTeC i2 / GPX export).
   - `lib/ui/settings/`:
     - `settings_screen.dart` (Apple grouped settings, preferences).
     - `esp_pairing_screen.dart` (Radar scan, RSSI, pairing lifecycle).
     - `tank_calibration_screen.dart` (Fuel-tank lid and upright calibration).
     - `bike_profiles_screen.dart`, `import_bike_profile_screen.dart`, `bike_learning_screen.dart` (CAN bus DBC/JSON mapping).
   - `lib/ui/widgets/`:
     - `glass_surface.dart` (`GlassSurface`, `GlassIconButton`, `PrimaryAction`, `ContentGroup`, `SettingsRow`, `AppPageTitle`).
     - `apple_tab_bar.dart` (Sliding capsule navigation).
     - `tab_content_transition.dart` (Interruptible tab content transition).
     - `corner_gradient_breather.dart` (Directional lean feedback wash).
     - `slide_to_unlock.dart` (Dual swipe & accessible unlock).
     - `construction_spirit_level.dart` (Yellow builder's spirit level).
     - `phone_placement_animation.dart`, `bike_upright_animation.dart` (Calibration animations).
     - `season_summary_card.dart`, `gg_friction_card.dart`, `gg_friction_reticle.dart`, `gps_track_map_card.dart`.
3. **Calibration Subsystem:**
   - `calibrateFromTank({required double phoneRollDeg})`: Computes mounting offset \(\theta_{\text{offset}} = \theta_{\text{esp}} - \theta_{\text{phone}}\), sends command `0x02` via BLE, saves locally.
   - `calibrateUpright()`: Computes offset relative to 0.0°, sends command `0x02`, saves locally.
4. **Testing & Static Analysis:**
   - Always verify changes with:
     ```bash
     flutter analyze
     flutter test
     ```
   - Must achieve **0 warnings and 0 errors** on `flutter analyze`. All unit, widget, and motion tests must pass.
   - Integration tests: `flutter test integration_test/ride_flow_test.dart` (validates real SQLite persistence in demo mode).

---

## 7. Workflow & Repository Hygiene

- **Single Monorepo Source of Truth:**
  - Root directory: Monorepo root (e.g. `/Users/pocitac/Documents/MotoLogger` or `C:\Users\cqeta\MotoLogger`)
  - Subfolders: `/app`, `/firmware`, `/hardware`, `/docs`.
  - Never split the repository into detached standalone copies.
- **Git Branching:**
  - Direct work on `main` branch with clean, informative commits.
  - Remote repository: `https://github.com/cqeta1564/MotoLogger.git`.
