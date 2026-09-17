# MotoLogger interface

## Scope and platform

Flutter companion app: **Jízda → Historie → Nastavení**. Ride detail retains
route, forces, charts and export. Settings leads to pairing, tank/upright
calibration, motorcycle profiles, profile import and learning. Bluetooth,
GPS, SQLite, file imports/exports and Android Auto remain the existing services.
Android is the only checked-in host; minimum SDK 24. Flutter 3.44.0 / Dart 3.12
matches the existing dependency lock. There is no iOS host or Xcode in this
Linux environment. No deployment target is raised.

The product explicitly specifies light-only appearance in PROJECT.md §5.3.
Keep light appearance even when the OS is dark. Use the system font available
on each platform; no downloaded Apple font and no CSS font-family aliases.

## Foundations

- Canvas: #F2F2F7; content: #FFFFFF; primary text: #1C1C1E.
- Secondary text: #63636B; dividers: #E5E5EA; selection: pale blue.
- Accent: system-style blue (#0066CC), restricted to selection and actions.
- Feedback: green success, amber caution, red error, always accompanied by text
  or an icon. Unavailable telemetry uses an em dash, never a fabricated zero.
- Type: 34 large title, 22 section title, 17 body, 13 secondary (Flutter logical
  units, not native points). Respect OS text scaling; allow wrapping and scrolling.
- Spacing: 4 / 8 / 12 / 16 / 20 / 24 / 32. Content corners: 20–24;
  primary actions: minimum 54 high, radius 14; navigation: capsule.
- Touch controls: at least 48 logical units. Focus, pressed and selected states
  must remain perceivable. Essential actions have visible labels.

## Components and material

`GlassSurface` is the single bounded Flutter BackdropFilter approximation:
local blur, neutral tint, thin edge and soft shadow. It is **not Apple's native
Liquid Glass**. Use it for the floating tab bar and contextual control groups,
never per-row lists or behind entire screens. Related controls share a surface;
selected controls use a fill, not another blur. Content remains opaque.
`GlassIconButton`, `AppPageTitle`, `ContentGroup`, `SettingsRow` and
`PrimaryAction` establish consistent navigation, hierarchy and touch behavior.
Cupertino/Material presentations keep their framework dismissal and focus.

Flutter does not expose a reliable cross-platform reduced-transparency signal.
A persisted “Omezit průhlednost” preference disables all backdrop filters.
High contrast and accessible navigation also select opaque materials.
Respect reduced motion via MediaQuery in instructional animations; no decorative looping effects.

## Interaction and truthful states

Tabs retain their widget/scroll state. Android back first returns to the ride.
The ride has visible connection state, an explicit demo action, start, pause,
resume and save. Demo recordings are named as demo, never as connected hardware.
Disconnected hardware and absent GPS are labeled. Auto-lock remains speed based;
unlock supports both the visible slide control and an accessible button.
Recording/storage errors keep the ride recoverable and expose a retry.
History search/sort, selection, CSV import and ZIP/GPX/CSV export stay functional.
Settings do not claim encryption, SD-card readiness or a live connection without
service evidence. No server, account or additional top-level destination.

## Evidence

- [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple control grouping](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Apple touch and layout](https://developer.apple.com/design/tips/)
- [Flutter iOS feature status](https://docs.flutter.dev/platform-integration/ios/ios-latest)

Verification and known limitations are recorded in `review/VERIFICATION.md`.

## Motion and lean feedback

The tab selection is one sliding capsule (260 ms ease-out), with an interruptible
180 ms content fade around the retained IndexedStack. Ride controls resize in
220 ms. `AppMotion` disables these transitions for reduced motion or accessible
navigation; navigation and touch input remain available throughout.

`CornerGradientBreather` now paints bounded directional edge feedback, without
its former perpetual pulse or blur shaders. Negative calibrated lean lights the
left edge, positive lean the right. The original 1° dead zone and 45° full-scale
range remain: green through 15°, smoothly orange at 30°, red at 45° and above.
These are visual angle bands, not measurements of available grip. The numeric
left/right instruments remain the non-color equivalent. Telemetry changes blend
for 100 ms; unavailable or invalid data produces no wash. Reduced transparency
and high contrast use a narrow solid edge instead. Ordinary content stays opaque.
