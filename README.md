# FluxBar

FluxBar is a native macOS menu bar utility aimed at a single device profile: a 2026 MacBook Air with Apple Silicon and a notch display. The MVP focuses on three things:

- showing lightweight live signals in the menu bar
- explaining likely heating causes instead of dumping raw metrics
- degrading cleanly when notch-safe menu bar width becomes tight

## MVP Scope

- SwiftUI `MenuBarExtra` app with AppKit accessory activation
- Menu bar metrics: upload/download speed, memory, CPU usage, temperature when accessible
- Notch-aware auto fallback: `standard -> compact -> icon -> single metric`
- Dropdown panel with overview, heat-factor assessment, and top processes
- Lightweight trend cards for 1m / 5m / 30m windows
- Alert evaluation with debounce and cooldown-based notifications
- Settings for mode, refresh interval, thresholds, process sorting, alerts, and launch-at-login

## Run

```bash
cd /Users/alfred/Code/Apps/FluxBar
swift run FluxBar
```

## Open In Xcode

FluxBar now also includes a native macOS app project:

- project: `/Users/alfred/Code/Apps/FluxBar/FluxBar.xcodeproj`
- shared scheme: `FluxBar`

Open the project in Xcode, select the `FluxBar` scheme, then run or archive it like a normal menu bar app. The app target uses:

- `LSUIElement = YES` to stay out of the Dock
- `Info.plist` at `App/Resources/Info.plist`
- shared build settings from `Configs/*.xcconfig`

Because this machine currently exposes only Command Line Tools and not the full Xcode app, I could not run `xcodebuild` verification here. The project files were generated to match the already working Swift sources.

## Current Data Availability Notes

- CPU usage: available
- memory occupancy and swap estimate: available
- upload/download speed: available from interface counters
- top processes: available from `ps`
- CPU/GPU temperature: best effort only

Temperature source priority is:

1. `macmon` (preferred for direct CPU/GPU die temperatures)
2. root helper cache (`/Users/Shared/FluxBar/thermal-cache.json`, generated via `powermetrics`)
3. AppleSmartBattery temperature proxy
4. macOS `ProcessInfo.thermalState` (qualitative fallback)

Install `macmon`:

```bash
cd /Users/alfred/Code/Apps/FluxBar/Scripts
./install-macmon.sh
```

`install-macmon.sh` now installs to `~/.local/bin/macmon` when Homebrew/MacPorts are unavailable, so it does not require sudo in the fallback path.

Install root thermal helper (optional fallback if `macmon` is unavailable):

```bash
cd /Users/alfred/Code/Apps/FluxBar/Scripts
sudo ./install-thermal-helper.sh
```

User notifications are only enabled when FluxBar is launched as a bundled `.app`. In `swift run` mode, FluxBar automatically disables notifications to avoid `UNUserNotificationCenter` runtime issues outside an app bundle.

## MVP Architecture

- `FluxBarApp.swift`: menu bar app entrypoint
- `SystemMonitor.swift`: sampling loop and local history
- `HeatAnalyzer.swift`: rule-based heating-cause inference
- `MenuBarUI.swift`: menu bar label, dropdown panel, settings
- `FluxBarSettings.swift`: persisted user preferences and launch-at-login wiring
- `NotificationSupport.swift`: guards notification features when running outside a real app bundle
- `FluxBar.xcodeproj`: native Xcode app project for running, signing, and archiving
- `App/Resources`: app `Info.plist` and asset catalog
- `Configs/*.xcconfig`: shared build settings for Debug and Release

## Enhancement Roadmap

### P1

- Replace best-effort temperature probing with a privileged helper or signed sensor bridge
- Improve the current 1m / 5m / 30m sparkline trends with denser sampling and persisted history
- Upgrade the current alert system with richer local notifications and per-alert controls
- Improve notch width estimation using runtime status item geometry

### P2

- Add memory pressure and swap trend correlation
- Add better per-process network attribution
- Add exportable diagnostic summary
- Add rule tuning from device-specific baselines collected over time

## Key Implementation Notes

- The heat engine is intentionally conservative. It outputs a workload-based estimate, not a hardware-level diagnosis.
- When temperature sensors are unavailable, confidence is reduced and the UI says so.
- Process sampling runs slower than CPU/memory/network sampling to keep the app itself lightweight.
