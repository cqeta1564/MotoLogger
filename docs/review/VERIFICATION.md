# Liquid Glass UI verification — 17 September 2026

## Implementation

Flutter remains the application stack; Android packaging, permissions, BLE/GPS,
SQLite schema, imports/exports, and Android Auto service are retained. No website,
SwiftUI rewrite, renderer dependency, paid service, firmware, or hardware changes.
The checked-in Android minimum remains API 24. There is no checked-in iOS host.

The shared `GlassSurface` uses clipped `BackdropFilter` blur, neutral tint, edge
highlight and elevation for navigation and contextual controls. This is an
approximation, not Apple's native Liquid Glass. Content is opaque. The product's
explicit light-only policy is preserved, including with a dark system appearance.

Changed screens: ride (including landscape and lock), history/search/selection,
ride detail, settings, pairing, calibration, profiles, learning, and profile import.
Secondary screens keep their workflows and now share back controls/system fonts.

Main changes: `app/lib/core/theme/app_theme.dart`,
`app/lib/core/preferences/app_preferences.dart`, `app/lib/main.dart`,
`app/lib/ui/widgets/glass_surface.dart`, `app/lib/ui/widgets/apple_tab_bar.dart`,
`app/lib/ui/dashboard/dashboard_screen.dart`, `app/lib/ui/history/`, and
`app/lib/ui/settings/`. Recording operations retain buffered samples on write
failure and serialize start/save/flush operations in `telemetry_manager.dart`.
Calibration no longer fabricates phone sensor readings when the sensor fails.

## Toolchain and baseline

- Arch Linux x86_64; Flutter **3.44.0** (revision `559ffa3f75`), Dart **3.12.0**.
- Installed SDK at `/home/bartaceq/.local/share/motologger-flutter`, matching the
  minimum in the original lockfile. No Flutter SDK was initially on PATH.
- OpenJDK 17.0.20.1; existing AGP 9.1.0 / Gradle 9.3.1 configuration retained.
- Android SDK at `/home/bartaceq/Android/sdk`; API 36 emulator, emulator 37.1.11.
- The first Android build installed the NDK/CMake/platform packages required by
  the existing plugins. Flutter generated its ignored Gradle wrapper files.
- `flutter pub get` resolved six SDK-pinned transitive versions for Flutter 3.44.0.
  `integration_test` is the only added direct dependency (development-only).
- Baseline `flutter analyze`: **no issues**. Baseline existing tests: **52 passed**;
  a temporary before-image capture test also passed (53 total during that run).

## Reproducible commands

From the checkout on this machine:

```sh
export PATH="/home/bartaceq/.local/share/motologger-flutter/bin:$PATH"
export ANDROID_HOME="/home/bartaceq/Android/sdk"
export GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=2'
cd /home/bartaceq/MotoLogger/app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d emulator-5554 --no-enable-impeller
```

Use a test phone/device ID from `flutter devices` instead of `emulator-5554` for
hardware. The renderer switch above is an **emulator workaround only**, not a
change to the app's production renderer or Android configuration.

For the local emulator:

```sh
$ANDROID_HOME/emulator/emulator -avd VibeOS_Phone -no-window -no-audio \
  -no-boot-anim -no-snapshot -memory 2048 -cores 2 -skin 720x1280 \
  -gpu swiftshader -feature -Vulkan
# After boot, in a second terminal:
$ANDROID_HOME/platform-tools/adb shell wm density 320
GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=2' \
  flutter test integration_test/ride_flow_test.dart -d emulator-5554 \
  --no-uninstall --no-enable-impeller
```

This integration test creates explicitly labeled demo rides in the emulator's
real SQLite database and sets the opaque-material preference. Do not run it
against production rider data. It uses the existing simulation, not fake claims
of a hardware connection.

Review images can be regenerated with Flutter's own widget renderer:

```sh
FLUTTER_ROOT=/home/bartaceq/.local/share/motologger-flutter \
  flutter test test/liquid_glass_test.dart --dart-define=CAPTURE_REVIEW=true
```

## Behavior and review coverage

- Disconnected launch; explicit demo; start; pause; resume; save; visible retry
  on start/storage failure; buffered data retained through a failed write.
- Duplicate start protection, history refresh, search and sort, bulk selection,
  imports/GPX/CSV/ZIP generation, route/G-force analytics, and back navigation.
- Retained tab state; database-backed material preference and opaque high-contrast
  fallback (asserts no `BackdropFilter` is present).
- 320×568, 390×844, 430×932 and 844×390 Flutter logical viewports. The 430×932 case
  uses 1.8× text and dark system appearance while the app remains light.
- Profile validation and unsaved-edit confirmation with 1.5× text and 280 logical
  units of keyboard inset. Cancelling dismissal retains the input.
- Reduced-motion instructional animations stop; no repeating unlock shimmer.
  Native screen-reader interaction and physical touch/glove ergonomics are not
  established by these widget checks.

Reviewed image defects and corrections: save notification obscuring tabs (moved
above navigation and made transient); excessive instrument height on short screens (reduced and
added compact landscape layout); clipped sort choices (adaptive segmentation),
small detail metrics (wrapping pairs), and oversized profile input actions
(wrapping controls and an expanding editor so validation remains visible). Test-font artifacts were corrected for the after captures.

`before-*.png` are exploratory pre-change widget captures; some original icon
fonts were not loaded, so they are not approved pixel-regression baselines.
`after-*.png` are actual Flutter widget renders, with built-in demo telemetry and
an explicit in-memory test database. They are not screenshots of an iPhone.
`android-*.png` are captures from the running Android Flutter surface. No fake
status bar, device frame, or Dynamic Island has been drawn.

## Runtime limits

Two initial Android emulator attempts lost ADB connectivity after app launch
with the default renderer. A subsequent Skia run completed the integration scenario. During the normal APK
relaunch, Android System UI showed an ANR dialog; restarting System UI recovered
the emulator and the native permission dialogs appeared.
The original `watchPerformance` helper failed to connect to its VM-service
WebSocket, so the integration test collects `SchedulerBinding` frame timings
instead. Any timings are emulator/debug diagnostics, not physical-device FPS.

NOT RUN: Xcode/iOS compilation or simulator (Linux and no iOS host), physical
ESP32 pairing/commands/calibration, real GPS accuracy, physical-phone performance,
Android Auto head unit, native screen-reader session, and OS share-sheet delivery.
Unit tests verify export contents; no external messages or real records were sent.
Existing plugin build warnings about future built-in Kotlin compatibility remain;
no dependency migration was introduced for this UI task.

## Final command results

| Check | Result |
| --- | --- |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 57 tests, including recording failure/retry and transient save notification |
| `flutter test test/liquid_glass_test.dart --dart-define=CAPTURE_REVIEW=true` | PASS — 5 tests; screenshots regenerated and inspected |
| `flutter build apk --debug` | PASS — final normal app APK |
| `flutter test integration_test/ride_flow_test.dart -d emulator-5554 --no-enable-impeller --no-uninstall` | PASS — 1 integration scenario, 42 s excluding build/install |
| `git diff --check` | PASS |

The native scenario uses the built-in demo and **real SQLite**. It checks start,
pause, resume, save, non-empty stored samples, history, loaded detail, back,
settings, and persisted opacity after reconstructing services. Initial test
harness failures were corrected: awaiting native data before screenshots and
scrolling virtualized rows clear of navigation before tapping. No checks were
disabled. The final transient-toast adjustment is covered by the widget test and
included in the normal APK; the native workflow pass preceded that adjustment.
A normal-APK review also found white system status icons on History. The app
now requests dark system icons across its light screens, without drawing any
fake system chrome. The corrected contrast was inspected in the final normal
APK on Ride and History.

The final normal APK is `app/build/app/outputs/flutter-apk/app-debug.apk` (ignored
build artifact; rebuild with the command above). The integration command replaces
that path with its test harness APK, so rebuild the normal app before sharing it.

### Captures and frame diagnostics

Inspected `after-*.png` and `android-*.png` in this directory. Native images cover
disconnected, recording, paused, history, loaded detail, settings and opaque
materials. The integration images precede the final transient-toast correction;
the final widget captures verify its dismissal. No motion recording was produced.

`android-frame-timings.json` contains 9 reported frames during demo scrolling:
build durations 53.8–73.9 ms, raster durations 24.5–118.5 ms. Method:
`SchedulerBinding.addTimingsCallback`, debug APK, Android 36 x86_64 AVD
`VibeOS_Phone`, 720×1280 pixels / density 320, Skia on SwiftShader, Linux host.
The test pumps frames and a host build was also running. These sparse, slow
software-emulator diagnostics **do not establish smoothness or physical-device
performance**; no FPS claim is made. Profile-mode measurement on a real phone
remains required.

### Normal APK relaunch

Installed the final normal APK with `adb install -r`, then used
`adb shell am force-stop com.motologger.app` and
`adb shell am start -n com.motologger.app/.MainActivity --ez enable-impeller false`.
Denied location and nearby-device permissions through Android's real dialogs;
the application remained usable and displayed “Bluetooth není dostupné”.
The SQLite file read after relaunch retained demo session 7 with 204 samples and
`reduce_transparency=true`. No database reset or clearing of app data was used.

Android Back from History returned to Ride without exiting the app. The native
permission-denied and relaunch-history images show the normal app with Android's
own status/navigation bars. The sample count above was queried from a read-only
copy of the emulator database. Failed early emulator runs left additional labeled
demo sessions; these were deliberately not erased and affect the history totals.

## Follow-up: sliding navigation and directional lean (1.0.1)

Restored the disconnected corner-feedback component to the ride screen, using
calibrated telemetry and the existing left-negative/right-positive convention.
Replaced its decorative repeating animation with a bounded, telemetry-driven
edge wash. Added interruptible tab selection/content transitions and action-panel
resizing, honoring reduced motion. Preserved the existing tab widget states.

- `flutter analyze`: no issues.
- `flutter test --reporter expanded`: 61 tests passed.
- `FLUTTER_ROOT=/home/bartaceq/.local/share/motologger-flutter flutter test
  test/motion_and_lean_test.dart --dart-define=CAPTURE_REVIEW=true`: 4 passed.
- New tests cover intermediate selector positions, interrupted direction changes,
  reduced motion, angle palette, invalid data, immediate disconnect clearing,
  opaque fallback and returning to the ride destination.
- Inspected actual widget-rendered `lean-left-green.png`, `lean-right-red.png`
  and `tab-slide-midpoint.png`: directional wash is visible in the margins,
  content remains readable, and the selection capsule is visible mid-transition.
  Also captured `lean-left-orange.png` and `lean-disconnected.png`.
- These lean captures use explicitly simulated fixed angles. Physical sensor
  direction/latency and physical-phone performance remain NOT RUN (no hardware).

Android follow-up verification:

- `flutter test integration_test/ride_flow_test.dart -d emulator-5554
  --no-enable-impeller --no-uninstall`: PASS, 1 integration test / 24 seconds
  after the build. Android 16 / API 36 x86_64 emulator, software rendering.
- The initial Android run exposed `RenderAnimatedSize` layout re-entry with
  zero-duration motion. Fixed by bypassing AnimatedSize when reduced motion is
  enabled; added widget coverage for starting/pausing in that mode. Re-ran all
  61 tests and analysis successfully, then the Android integration successfully.
- Retrieved and inspected `android-motion-ride-recording.png` and
  `android-motion-ride-paused.png`. This emulator retained opaque-material
  preferences, so these images also show the solid-edge fallback. Content is
  scrollable below the floating controls. No additional visual defect identified
  in the changed selector or edge feedback. Screenshots do not measure motion.
- No frame-rate claim; physical phone and real ESP32 checks remain NOT RUN.

Rebuild this version from `app/` (existing local Flutter/Android SDK):

```sh
export PATH=/home/bartaceq/.local/share/motologger-flutter/bin:$PATH
export ANDROID_HOME=/home/bartaceq/Android/sdk
export GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=2'
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
```

The existing personal-test signing configuration is unchanged. Open the supplied
APK on the Android phone to install/update; no need to uninstall the previous app.

Release delivery: universal 1.0.1+2 built successfully in 36 seconds (53.9 MB);
`apksigner verify` passed. APK contains armeabi-v7a, arm64-v8a and x86_64.
Copied to `/mnt/nas/Apps/MotoLogger-1.0.1-android.apk` and
`/home/bartaceq/Downloads/MotoLogger-1.0.1-android.apk`, preserving version 1.0.0.
Source and NAS SHA-256 match:
`c39338813e0dbd3d2b253440f0e468357d6c9066702ce45aaefe4fdc5bdc8aa3`.
Installed the regular release APK over the emulator integration build and launched
with `adb shell am start -n com.motologger.app/.MainActivity --ez enable-impeller false`.
