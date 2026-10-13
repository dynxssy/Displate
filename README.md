# Displate

A polished macOS menu bar app for controlling every connected display: brightness, contrast,
resolution, refresh rate and HiDPI, with global keyboard shortcuts and a native-style on-screen indicator.

Written from scratch in Swift / SwiftUI (no third-party dependencies). Requires macOS 14 Sonoma or later
and runs on both Apple silicon and Intel Macs.

## Features

| | |
|---|---|
| **Brightness** | Built-in & Apple displays via DisplayServices, external monitors via **DDC/CI** (Apple silicon), anything else via software (gamma) dimming. Smooth animated transitions. |
| **Contrast** | DDC/CI contrast slider for external monitors that support it. |
| **Sync brightness** | One slider/shortcut drives all displays together. |
| **Resolutions** | Tap-to-switch resolution grid, refresh rate picker and a full "All modes" list. |
| **HiDPI** | One-tap / one-key toggle between the HiDPI (crisp, 2×) and low resolution variant of the current size. For monitors where macOS offers no HiDPI modes, **Unlock HiDPI modes…** installs a standard display override (asks for your admin password, removable any time). |
| **Shortcuts** | System-wide hotkeys acting on the display under the mouse pointer. Fully re-assignable in Settings. No Accessibility permission needed. |
| **On-screen indicator** | System-style HUD with segmented level bar and animated symbols. |
| **Launch at login** | Via the modern `SMAppService` API. |

### Default shortcuts

| Action | Shortcut |
|---|---|
| Brightness up / down | `⌃⌥⌘ ↑` / `⌃⌥⌘ ↓` |
| Next resolution (more space) | `⌃⌥⌘ →` |
| Previous resolution (larger text) | `⌃⌥⌘ ←` |
| Toggle HiDPI | `⌃⌥⌘ H` |

## Getting the app

**Prebuilt:** every push builds a universal app on GitHub Actions. Open the latest run of the
**Build** workflow, download the `Displate` artifact, unzip, and move `Displate.app` to `/Applications`.
Because it is ad-hoc signed, the first launch needs a right-click → **Open** (or
`xattr -dr com.apple.quarantine /Applications/Displate.app`).

**Build yourself** (Xcode or the Command Line Tools):

```bash
./scripts/build-app.sh              # native architecture
./scripts/build-app.sh --universal  # arm64 + x86_64 (needs Xcode)
cp -R build/Displate.app /Applications/ && open /Applications/Displate.app
```

## Notes

- **DDC/CI** must be enabled in your monitor's on-screen menu (usually on by default). Some docks and
  HDMI adapters don't pass DDC through; for those monitors turn on *Software dimming* in the display's card.
  The built-in HDMI port on some M1/M2 Macs does not support DDC.
- **HiDPI unlock** writes `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-*/DisplayProductID-*`.
  Reconnect the monitor (or log out and in) for new modes to appear. Use *Remove HiDPI unlock* to undo.
- Software dimming is reset by macOS when the app quits and restored when it starts again.

## Project layout

```
Sources/Displate/
  DisplateApp.swift   App entry, menu bar extra & settings scenes
  AppState.swift      Display model, actions, shortcut handling
  MenuView.swift      Menu bar UI (display cards, sliders, resolution grid)
  SettingsView.swift  Settings window & shortcut recorder
  HUD.swift           On-screen indicator
  Brightness.swift    DisplayServices / DDC / gamma brightness backends
  DDC.swift           DDC/CI over IOAVService (Apple silicon)
  DisplayModes.swift  Display mode enumeration & switching
  HiDPI.swift         HiDPI toggle & display override installer
  Hotkeys.swift       Carbon global hotkeys
scripts/
  build-app.sh        Builds and ad-hoc signs build/Displate.app
  make-icon.swift     Renders the app icon
```
