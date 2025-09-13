BigWatt - Big Watts in your menubar

Overview
- Shows the current AC adapter wattage (e.g., 65W) in the macOS menu bar.
- Updates automatically on power changes via IOKit notifications

Build
1) Ensure Xcode command line tools are available: `xcode-select -p`
2) Build release binary:
   - `swift build -c release`
3) Run it:
   - `.build/release/WattageBar`

Bundle as an app
- Create a macOS `.app` bundle you can install:
  1) Make the script executable: `chmod +x scripts/make_app.sh`
  2) Run: `scripts/make_app.sh`
  3) The bundle is at `dist/WattageBar.app`. Launch with `open dist/WattageBar.app`.

Install / launch at login
- Drag `dist/WattageBar.app` into System Settings → General → Login Items.
- Alternatively, right-click `WattageBar.app` → Open (first run to approve, if unsigned).

Notes

Notes
- When on battery, the item shows `Batt`. When on AC but wattage is unavailable, it shows `AC`.
- On most Macs, wattage comes from `IOPSCopyExternalPowerAdapterDetails` using `kIOPSPowerAdapterWattsKey`.
- The app runs as a background menu bar app (via `LSUIElement`).
- To launch at login, add the app bundle to Login Items in System Settings.
