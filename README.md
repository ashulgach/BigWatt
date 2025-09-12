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

Notes
- When on battery, the item shows `Batt`. When on AC but wattage is unavailable, it shows `AC`.
- On most Macs, wattage comes from `IOPSCopyExternalPowerAdapterDetails` using `kIOPSPowerAdapterWattsKey`.
- To launch at login, add the built binary to Login Items in System Settings, or wrap this into an app bundle if desired.

