# 󰍛 Omarchy Hardware Monitor (`omarchy-sysmon`)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%20Hyprland-orange.svg)](https://github.com/Madhukumar511/omarchy-sysmon)
[![Zero Battery Drain](https://img.shields.io/badge/Battery%20Optimized-~1ms%20Runtime-brightgreen.svg)](#battery-friendly--ultra-low-overhead)

A high-craftsmanship, native Hardware Monitor widget and interactive telemetry card designed specifically for the **Omarchy Desktop Shell** (`Quickshell` on Arch Linux / Hyprland).

Designed to match the aesthetic and fluid animations of Omarchy's **World Clock** (`omarchy.elsewhen`), featuring velvety blended surfaces, smooth gliding circular thumbs, and genuine Linux hardware telemetry.

---

## ⚡ Quick 1-Line Installation (For You and Others)

To install on any Omarchy system, simply run:

```bash
curl -fsSL https://raw.githubusercontent.com/Madhukumar511/omarchy-sysmon/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/Madhukumar511/omarchy-sysmon.git ~/.config/omarchy/plugins/atomic.sysmon
~/.config/omarchy/plugins/atomic.sysmon/install.sh
```

The installer automatically:
- Registers the widget into your Omarchy status bar layout (`~/.config/omarchy/shell.json`).
- Initializes hardware caching for zero battery drain.
- Reloads the shell seamlessly with `omarchy restart shell`.

---

## ✨ Features

- **Genuine Hardware Telemetry**:
  - **Real Intel GPU %**: Measured from genuine **RC6 sleep residency deltas** (`rc6_residency_ms`), reporting true 0–5% at desktop idle rather than fake frequency ratios.
  - **State-Delta CPU Engine**: Non-blocking `/proc/stat` delta intervals calculated in under **1 millisecond** without synthetic blocking sleep bursts.
  - **Dynamic Thermal Tracking**: Package and per-core temperature sensors from `hwmon` with instant **°C ⇄ °F** switching.
  - **Hardware Fan Speed**: Dell SMM and generic Linux hardware fan RPM with spinning blade animations.
  - **Memory & 1-Minute Load**: Real-time RAM allocation and Linux load averages.
- **World-Clock (`elsewhen`) Aesthetics**:
  - **Velvety Toned Rows**: Dynamic background mixes that adapt to any Omarchy theme.
  - **DaylightStrip Slider Tracks**: 3px progress tracks with signature smooth Bezier-eased sliding circular thumbs (`Easing.OutCubic`).
  - **Hero Title**: Centered `Hardware 󰍛 Telemetry` header with spinning glyph and system specs subtitle.
- **Battery-Friendly & Ultra-Low Overhead**:
  - **Zero CPU Drain**: Hardware paths (`hwmon`, `fan`, `rc6`) are cached after first discovery; direct sysfs reads take `< 1.2ms`.
  - **Adaptive Polling**: Automatically slows down polling to **4.5s** when running on battery (`Discharging`) to protect deep CPU C-states, and increases to **1.2s** only when the popup is actively open.
- **Calm Thermal Profile (No False Alarms)**:
  - Modern laptop processors frequently turbo-boost to 85°C–92°C for short bursts. The status bar widget remains calm and never continuously flashes or turns red on routine thermal spikes. Red alerts are reserved strictly for true thermal throttle limits (≥96°C).
- **Interactive Multi-Mode Status Bar**:
  - **Right-Click or Scroll Wheel** on the bar widget to cycle across 4 view modes:
    1. **Overview**: ` 12%   󰢮 3%   󰈐 Off`
    2. **Thermals**: ` 54°C   󰈐 2.4k`
    3. **Clocks**: ` 2.10 GHz   󰢮 300 MHz`
    4. **Memory & Load**: ` 4.2G (27%)   󰓅 1.15`
- **Native Keyboard Shortcuts**:
  - `B`: Instantly launch or focus `btop` dashboard.
  - `R`: Force instant telemetry refresh.
  - `Tab`: Switch bar view mode.
  - `Esc`: Close popup.
- **Shell IPC Scripting**: Full scriptable control:
  ```bash
  omarchy-shell atomic.sysmon toggle
  omarchy-shell atomic.sysmon next
  omarchy-shell atomic.sysmon refresh
  ```

---

## 🗑️ Uninstallation

To cleanly remove the plugin:

```bash
~/.config/omarchy/plugins/atomic.sysmon/uninstall.sh
```

---

## 📄 License

MIT © [Madhukumar511](https://github.com/Madhukumar511)
