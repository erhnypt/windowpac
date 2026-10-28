import Cocoa
import IOKit.ps

struct BatteryRow: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let percent: Int
    let charging: Bool
    let detail: String?
}

enum BatteryReader {
    /// The Mac's own battery (nil on desktops without one).
    static func mac() -> BatteryRow? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let full = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return BatteryRow(id: "mac", name: Host.current().localizedName ?? "Mac", symbol: "laptopcomputer",
                              percent: full > 0 ? cur * 100 / full : cur, charging: charging,
                              detail: onAC && !charging ? "Plugged in" : nil)
        }
        return nil
    }

    /// Connected Bluetooth devices that report a battery level (blocking: ~1 s, call off the main thread).
    static func bluetooth() -> [BatteryRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        func pct(_ v: Any?) -> Int? { (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
        var rows: [BatteryRow] = []
        for c in controllers {
            for entry in (c["device_connected"] as? [[String: Any]] ?? []) {
                for (name, v) in entry {
                    guard let dev = v as? [String: Any] else { continue }
                    let main = pct(dev["device_batteryLevelMain"])
                    let l = pct(dev["device_batteryLevelLeft"]), r = pct(dev["device_batteryLevelRight"])
                    let cs = pct(dev["device_batteryLevelCase"])
                    guard let level = main ?? [l, r].compactMap({ $0 }).min() else { continue }
                    var parts: [String] = []
                    if let l { parts.append("L \(l)%") }
                    if let r { parts.append("R \(r)%") }
                    if let cs { parts.append("Case \(cs)%") }
                    let kind = ((dev["device_minorType"] as? String) ?? "").lowercased()
                    let symbol = kind.contains("mouse") ? "computermouse"
                        : kind.contains("keyboard") ? "keyboard"
                        : kind.contains("trackpad") ? "hand.point.up.left"
                        : kind.contains("airpod") ? "airpods"
                        : (kind.contains("headphone") || kind.contains("headset")) ? "headphones"
                        : kind.contains("game") ? "gamecontroller" : "wave.3.right"
                    rows.append(BatteryRow(id: "bt-" + name, name: name, symbol: symbol, percent: level,
                                           charging: false, detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
                }
            }
        }
        return rows.sorted { $0.name < $1.name }
    }
}

final class BatteryModel: ObservableObject {
    @Published var rows: [BatteryRow] = []
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let mac = BatteryReader.mac()
            let bt = BatteryReader.bluetooth()
            DispatchQueue.main.async { self.rows = (mac.map { [$0] } ?? []) + bt }
        }
    }
}
