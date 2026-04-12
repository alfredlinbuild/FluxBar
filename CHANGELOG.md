# Changelog

## 0.1.0 - 2026-04-08

- Established the first self-use stable baseline for FluxBar.
- Built the native macOS menu bar app architecture with `NSStatusItem + NSPopover`.
- Implemented menu bar metrics for temperature, CPU, memory, and network with notch-aware compact layout.
- Added overview, trends, heat factor analysis, alerts, and top process diagnostics in the panel UI.
- Added historical sample persistence and a lightweight diagnostic export path.
- Integrated temperature reading via `macmon` as the primary source, with fallback paths retained.
- Added local helper scripts for experimental root-based thermal sampling fallback.
