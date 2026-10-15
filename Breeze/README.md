# Breeze

Menu bar temperatures and fan control for your Mac: automatic, fixed, or following a temperature
curve you draw. Same design and build setup as [Displate](../README.md) and [Unload](../Unload/README.md).
Swift / SwiftUI, no dependencies, macOS 14+.

## Features

| | |
|---|---|
| **Menu bar** | Fan icon with live CPU temperature (or fan RPM, or icon only). Turns red at 90 °C. |
| **Status** | CPU and GPU temperature with a 3-minute history, a fan glyph that spins with the real fan speed, and each fan's RPM within its min/max range. |
| **Auto** | macOS controls the fans (the default; nothing is written). |
| **Fixed** | One slider; each fan is set to the same position within its own range. |
| **Curve** | Fan speed follows temperature. Drag the four points of the curve; the live marker shows the current temperature and the applied speed. Pick the sensor to follow (CPU, GPU or hottest) and start from the Quiet, Balanced or Performance presets. Speed rises quickly and falls slowly, so the fans don't pulse. |
| **Fanless Macs** | MacBook Air and other fanless Macs show temperatures only. |
| **°C / °F**, launch at login | In Settings. |

## How fan control works

Reading temperatures and fans works for any user. **Changing fan speed requires root**, so on first
use Breeze asks for your administrator password once and installs a small helper:

- `/Library/PrivilegedHelperTools/app.displate.Breeze.helper` (launch daemon)
- `/Library/LaunchDaemons/app.displate.Breeze.helper.plist`

The helper only does SMC fan writes, only accepts connections from `Breeze.app`, and keeps targets
within each fan's minimum and maximum. **Fans return to automatic** when:

- you switch to Auto,
- Breeze quits or crashes (the connection drops),
- Breeze sends no command for 30 seconds,
- the helper is stopped or uninstalled.

Settings → **Uninstall…** removes both files.

On Apple silicon the helper first unlocks manual mode (`Ftst`), then sets `F<n>Md` and `F<n>Tg`.
On Intel Macs it uses `F<n>Md` or the `FS! ` bitmask with `F<n>Tg`.

## Building

```bash
./scripts/build-app.sh              # native architecture
./scripts/build-app.sh --universal  # arm64 + x86_64 (needs Xcode)
cp -R build/Breeze.app /Applications/ && open /Applications/Breeze.app
```

Install it in `/Applications`: the helper only trusts `…/Breeze.app/Contents/MacOS/Breeze`.
Every push also builds it on GitHub Actions (the `Breeze` artifact of the **Build** workflow).
It is ad-hoc signed, so the first launch needs right-click → **Open**.
