# MotoLogger Mobile: Motorcycle Telemetry Dashboard

[![Flutter](https://img.shields.io/badge/Flutter-Android_&_iOS-blue.svg)](https://flutter.dev/)
[![Android Auto](https://img.shields.io/badge/Android_Auto-Compatible-green.svg)](https://developer.android.com/training/cars/apps)
[![Apple CarPlay](https://img.shields.io/badge/Apple_CarPlay-Ready-black.svg)](https://developer.apple.com/carplay/)
[![Offline](https://img.shields.io/badge/Storage-100%25_Offline_SQLite-orange.svg)](https://sqlite.org/)

The official companion mobile application for the **MotoLogger (ESP32-S3)** telemetry datalogger. Designed for motorcycles, race track days, and road trips, featuring high-rate BLE streaming, internal smartphone GPS fusion, and projection onto **Android Auto** and **Apple CarPlay** head units.

---

## Key Features

- **25 Hz Real-Time BLE Stream:**
  - Auto-discovers and connects to `MotoLogger-ESP32` in the background.
  - Zero-copy binary deserialization (28-byte packet) with minimal CPU and battery usage.
- **Vibration-Resistant Lean Angle Gauge (CustomPainter):**
  - Continuous roll angle arc (-60° to +60°) with dynamic horizon needle.
  - Color-coded safety zones (Cyan = Cruising, Amber = Aggressive, Red = Track Knee-Down).
  - Peak Left and Peak Right markers remembered throughout the ride.
- **Friction Circle (G-G Diagram):**
  - 1.5G concentric circles displaying combined braking, acceleration, and lateral cornering forces.
- **Tachometer & Gear Indicator:**
  - Dynamic RPM bar with programmable Shift Light warning.
  - Prominent neutral `N` and gear digit display (`1` through `6`).
- **One-Touch Zero Tare:**
  - Direct remote calibration button in the app to zero the baseline lean angle when the bike is level.
- **100% Offline & Serverless (Local SQLite):**
  - Fully functional in mountain passes, forests, and remote tracks without internet access.
  - Automatic session logging with GPS coordinates, altitude, speeds, and lean angles.
  - Export sessions to **CSV** (for MoTeC i2, RaceRender, TrackAddict) or **GPX** (for Google Earth).
- **Built-in Demo Simulation Mode:**
  - Tap the bolt (`⚡`) icon in the top app bar to simulate live telemetry without needing the physical bike or ESP32 board.

---

## Projection on Android Auto & Apple CarPlay

### Android Auto Setup (Motorcycle Head Unit)
1. On your Android phone, go to **Settings > Android Auto**.
2. Scroll to the bottom and tap **Version** 10 times to enable **Developer Mode**.
3. Open the top-right 3-dot menu > **Developer settings**.
4. Check **Unknown sources** to permit custom telemetry apps.
5. Plug or pair your phone with your motorcycle display (e.g. Chigee AIO-5, Carpuride, Ottocast).
6. Launch **MotoLogger** from the vehicle app drawer.

### Apple CarPlay
- For developer deployment, build with Xcode targeting your iOS device.

---

## Getting Started

### Prerequisites
1. [Flutter SDK](https://docs.flutter.dev/get-started/install) (version >= 3.2.0)
2. Android Studio or VS Code with Flutter Extension

### Running the App
```bash
# Clone or navigate to the repository
cd MotoLogger-App

# Fetch dependencies
flutter pub get

# Run on connected smartphone or emulator
flutter run
```

---

## License
Open-source under MIT License.
