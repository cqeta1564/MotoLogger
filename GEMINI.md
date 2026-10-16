# MotoLogger Workspace Rules (GEMINI.md)

This repository is governed by the unified agent and coding guidelines defined in [`AGENTS.md`](./AGENTS.md).

### Quick Summary of Mandatory Rules:
1. **Chat Language:** Always communicate with the user in **Czech** (Čeština).
2. **Code & Comments:** All code, comments, variables, documentation, and git commits must strictly be in **English**.
3. **Design System (Pure Apple Aesthetic + GlassSurface):**
   - Cupertino light theme (`#F2F2F7` / `#FFFFFF`, `#1C1C1E`). Dark system icons (`SystemUiOverlayStyle.dark`).
   - `GlassSurface` is a bounded `BackdropFilter` approximation used *only* for floating navigation (`AppleTabBar`) and floating action panels. Content remains opaque. Never use blurs across entire screens or per-row.
   - Respect persisted `reduce_transparency` ("Omezit průhlednost") fallback to crisp solid opaque surfaces.
   - Strictly NO dark neon glow, generic gradients, robotic "futuristic AI" aesthetics, or generic AI phrases.
4. **Navigation & Motion:**
   - 3 tabs: **Jízda** → **Historie** → **Nastavení**. Retained `IndexedStack` state. Android Back returns to Jízda first.
   - Respect `AppMotion` and OS reduced-motion settings (bypass sliding capsule / resize transitions to avoid layout glitches).
5. **Truthful Telemetry & State:**
   - Use em-dash (`—`) for missing sensor/BLE data (never fake 0.0°).
   - Real hardware vs. demo ("Vyzkoušet demo") are explicitly separated. Demo sessions are stored with `isDemo: true`.
   - Buffered samples are preserved on SQLite save failure with an explicit retry option.
6. **Ergonomics:** Large touch targets (≥ 48 pt), uniform button heights (`54 px`, radius `14 px`), speed-based auto-lock (> 5 km/h) with dual swipe/accessible unlock, no technical jargon in rider-facing UI.
7. **Quality Gate:** Zero errors on `flutter analyze`, all unit and widget tests passing in `flutter test` (61+ tests), clean PlatformIO firmware compilation.
8. **Architecture & Hardware Reference:** Consult [`PROJECT.md`](./PROJECT.md) and [`AGENTS.md`](./AGENTS.md) for full specifications.
