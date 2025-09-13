import AppKit
import IOKit
import IOKit.ps

// Helper to read current AC adapter wattage via IOKit
final class PowerAdapter {
    struct Reading {
        let isOnAC: Bool
        let watts: Int?
    }

    func current() -> Reading {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        var isOnAC = false
        if let t = snapshot,
           let type = IOPSGetProvidingPowerSourceType(t)?.takeUnretainedValue() as String? {
            isOnAC = (type == kIOPSACPowerValue)
        }

        var watts: Int? = nil
        if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            if let w = details[kIOPSPowerAdapterWattsKey as String] as? Int {
                watts = w
            } else if let num = details[kIOPSPowerAdapterWattsKey as String] as? NSNumber {
                watts = num.intValue
            }
        }
        return Reading(isOnAC: isOnAC, watts: watts)
    }
}

// Battery telemetry via IORegistry (AppleSmartBattery)
final class BatterySensor {
    struct Telemetry {
        let voltageMV: Int?
        let instantAmperageMA: Int?
        let isCharging: Bool?
        var powerWatts: Double? { // positive -> into battery, negative -> out
            guard let v = voltageMV, let i = instantAmperageMA else { return nil }
            return (Double(v) * Double(i)) / 1_000_000.0
        }
    }

    func read() -> Telemetry {
        let classes = ["AppleSmartBattery", "AppleSmartBatteryManager"]
        for cls in classes {
            if let match = IOServiceMatching(cls) {
                let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
                if service != 0 {
                    defer { IOObjectRelease(service) }
                    var unmanagedDict: Unmanaged<CFMutableDictionary>?
                    let kr = IORegistryEntryCreateCFProperties(service, &unmanagedDict, kCFAllocatorDefault, 0)
                    if kr == KERN_SUCCESS, let dict = unmanagedDict?.takeRetainedValue() as? [String: Any] {
                        let voltage = (dict["Voltage"] as? Int) ?? (dict["CurrentVoltage"] as? Int)
                        let instantA = (dict["InstantAmperage"] as? Int) ?? (dict["Amperage"] as? Int)
                        let charging = (dict["IsCharging"] as? Bool)
                        return Telemetry(voltageMV: voltage, instantAmperageMA: instantA, isCharging: charging)
                    }
                }
            }
        }
        return Telemetry(voltageMV: nil, instantAmperageMA: nil, isCharging: nil)
    }
}

// User settings for which metric to show in the menu bar
enum DisplayMetric: String, CaseIterable {
    case auto
    case soc
    case outlet
    case battery

    var title: String {
        switch self {
        case .auto: return "Auto (SoC/Outlet/Battery)"
        case .soc: return "SoC Load"
        case .outlet: return "Outlet Delivery"
        case .battery: return "Battery Load"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let displayMetricKey = "displayMetric"

    var displayMetric: DisplayMetric {
        get {
            if let raw = UserDefaults.standard.string(forKey: displayMetricKey),
               let metric = DisplayMetric(rawValue: raw) {
                return metric
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: displayMetricKey)
        }
    }
}

// C-compatible callback for IOKit power notifications
private func powerSourceCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let controller = Unmanaged<StatusController>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.update()
    }
}

final class StatusController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let adapter = PowerAdapter()
    private let battery = BatterySensor()
    private let settings = Settings.shared
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?

    init() {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = "—W"
        }

        statusItem.menu = NSMenu()

        // Register power source change notifications with a C-compatible callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let unmanaged = IOPSNotificationCreateRunLoopSource(powerSourceCallback, context) {
            let src = unmanaged.takeRetainedValue()
            self.runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
        }

        // Fallback periodic refresh (some adapters won’t emit notifications)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.update()
        }

        update()
    }

    @objc private func refreshAction(_ sender: Any?) {
        update()
    }

    @objc private func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    fileprivate func update() {
        let ac = adapter.current()
        let bat = battery.read()

        // Battery power: positive = charging, negative = discharging
        let battW = bat.powerWatts

        // Compute outlet delivery and SoC load via subtraction when possible
        var outletW: Double?
        var socW: Double?

        if ac.isOnAC {
            if let rated = ac.watts, rated > 0 {
                outletW = Double(rated)
                let chargeW = max(0.0, battW ?? 0.0)
                socW = max(0.0, Double(rated) - chargeW)
            } else {
                outletW = nil
                socW = nil
            }
        } else {
            outletW = 0.0
            if let bw = battW, bw < 0 { socW = -bw }
        }

        // Primary status text based on settings
        let statusText: String = {
            switch settings.displayMetric {
            case .soc:
                if let sw = socW { return String(format: "SoC %.1fW", sw) }
            case .outlet:
                if let ow = outletW {
                    if ac.isOnAC, ac.watts != nil { return String(format: "%.0fW", ow) }
                    return String(format: "Outlet %.1fW", ow)
                }
            case .battery:
                if let bw = battW { return String(format: (bw >= 0 ? "+%.1fW" : "%.1fW"), bw) }
            case .auto:
                if let sw = socW { return String(format: "SoC %.1fW", sw) }
                if let ow = outletW {
                    if ac.isOnAC, ac.watts != nil { return String(format: "%.0fW", ow) }
                    return String(format: "Outlet %.1fW", ow)
                }
                if let bw = battW { return String(format: (bw >= 0 ? "+%.1fW" : "%.1fW"), bw) }
            }
            return ac.isOnAC ? "AC" : "Batt"
        }()
        statusItem.button?.title = statusText

        // Build details menu (simple layout)
        if let menu = statusItem.menu {
            menu.removeAllItems()
            let outletStr: String = {
                if let ow = outletW {
                    if ac.isOnAC, ac.watts != nil { return String(format: "%.0f W (rated)", ow) }
                    return String(format: "%.1f W", ow)
                }
                return "—"
            }()

            let battStr: String = {
                guard let bw = battW else { return "—" }
                if bw > 0 { return String(format: "+%.1f W (charging)", bw) }
                if bw < 0 { return String(format: "%.1f W (discharging)", bw) }
                return "0.0 W"
            }()

            let socStr: String = {
                if let sw = socW { return String(format: "%.1f W", sw) }
                return "—"
            }()

            menu.addItem(withTitle: "Outlet: \(outletStr)", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Battery: \(battStr)", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "SoC Load: \(socStr)", action: nil, keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            let src = ac.isOnAC ? "AC" : "Battery"
            let state = (bat.isCharging == true) ? "Charging" : (ac.isOnAC ? "Not Charging" : "Discharging")
            menu.addItem(withTitle: "Source: \(src) — \(state)", action: nil, keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            // Settings: Display metric submenu
            let displayMenu = NSMenu()
            for metric in DisplayMetric.allCases {
                let item = NSMenuItem(title: metric.title, action: #selector(setDisplayMetric(_:)), keyEquivalent: "")
                item.target = self
                item.state = (metric == settings.displayMetric) ? .on : .off
                item.representedObject = metric.rawValue
                displayMenu.addItem(item)
            }
            let displayItem = NSMenuItem(title: "Display Metric", action: nil, keyEquivalent: "")
            displayItem.submenu = displayMenu
            menu.addItem(displayItem)

            menu.addItem(NSMenuItem.separator())
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction(_:)), keyEquivalent: "r")
            refreshItem.target = self
            menu.addItem(refreshItem)
            let quitItem = NSMenuItem(title: "Quit WattageBar", action: #selector(quitAction(_:)), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
        }
    }

    @objc private func setDisplayMetric(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let metric = DisplayMetric(rawValue: raw) {
            settings.displayMetric = metric
            update()
        }
    }
}

// App bootstrap (no storyboard, no dock icon)
class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
