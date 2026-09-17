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
  - Choose **Vyzkoušet demo** on the ride screen (or **Demo jízda** in Settings) to simulate telemetry and a Brno circuit GPS track. Demo rides are labeled as demo when saved. Save an active ride before changing its data source.

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
1. [Flutter SDK](https://docs.flutter.dev/get-started/install) (tested with Flutter 3.44.0 / Dart 3.12.0; see pubspec.lock)
2. Android Studio or VS Code with Flutter Extension

### Running the App
```bash
# Clone or navigate to the repository
cd MotoLogger/app

# Fetch dependencies
flutter pub get

# Run on connected smartphone or emulator
flutter run
```

The local `VibeOS_Phone` AVD must be running before selecting `emulator-5554`.
On this machine, start it in a separate terminal and leave that terminal open:

```bash
$ANDROID_HOME/emulator/emulator -avd VibeOS_Phone -no-window -no-audio \
  -no-boot-anim -no-snapshot -memory 2048 -cores 2 -skin 720x1280 \
  -gpu swiftshader -feature -Vulkan
```

Once `flutter devices` lists `emulator-5554`, run
`flutter run -d emulator-5554 --no-enable-impeller`. The renderer flag works
around a graphics failure in this software emulator; it is not an app setting.
The AVD command above runs without a desktop window. A visible emulator window
requires a working X11/Qt display connection on the host. On this machine,
the emulator's Qt window could not connect to the desktop, so its screen is
mirrored with the verified upstream `scrcpy` v4.1 release instead:

```bash
SDL_VIDEODRIVER=wayland \
  /home/bartaceq/.local/share/scrcpy-linux-x86_64-v4.1/scrcpy \
  -s emulator-5554 --no-audio --window-title MotoLogger
```

---

## License
Open-source under MIT License.

## Interface and verification

The interface keeps the product's light-only appearance. Floating navigation and
contextual controls use a bounded Flutter blur/tint approximation, **not native
Apple Liquid Glass**. Content stays opaque. Settings → **Omezit průhlednost**
persists an opaque fallback in SQLite. Android back and enlarged text are supported.

The repository currently contains an Android host only. iOS/CarPlay claims above
are product intentions, not a checked-in, buildable iOS target. No iOS simulator,
Xcode build or physical motorcycle validation was performed on this Linux machine.

See [design decisions](../docs/DESIGN.md) and the
[verification record and screenshots](../docs/review/VERIFICATION.md).

```bash
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

On an emulator or disposable test device, the integration test exercises the
built-in demo with real SQLite storage. It creates a labeled demo ride and sets
the opaque-material preference; it never contacts motorcycle hardware.

```bash
flutter test integration_test/ride_flow_test.dart -d <device-id> --no-uninstall
```
