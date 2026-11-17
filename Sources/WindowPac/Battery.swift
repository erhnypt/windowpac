import Cocoa
import IOKit
import IOKit.ps
import CoreBluetooth

struct BatteryRow: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let percent: Int
    let charging: Bool
    let detail: String?
}

enum BatteryReader {
    static func symbol(for text: String) -> String {
        let k = text.lowercased()
        return k.contains("mouse") || k.contains("mx anywhere") ? "computermouse"
            : k.contains("keyboard") || k.contains("keys") ? "keyboard"
            : k.contains("trackpad") ? "hand.point.up.left"
            : k.contains("airpod") ? "airpods"
            : (k.contains("headphone") || k.contains("headset") || k.contains("buds")) ? "headphones"
            : (k.contains("game") || k.contains("controller")) ? "gamecontroller" : "wave.3.right"
    }

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
                              detail: onAC && !charging ? L.t("Plugged in") : nil)
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
                    if let cs { parts.append(L.t("Case") + " \(cs)%") }
                    let kind = ((dev["device_minorType"] as? String) ?? "") + " " + name
                    let symbol = symbol(for: kind)
                    rows.append(BatteryRow(id: "bt-" + name, name: name, symbol: symbol, percent: level,
                                           charging: false, detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
                }
            }
        }
        return rows.sorted { $0.name < $1.name }
    }

    /// Keyboards, mice, trackpads, game controllers… that publish `BatteryPercent` in the IO registry
    /// (Apple Magic devices and most Bluetooth HID devices). system_profiler misses many of these.
    static func ioregistry() -> [BatteryRow] {
        var it: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        func prop(_ e: io_registry_entry_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        var rows: [String: BatteryRow] = [:]
        var e = IOIteratorNext(it)
        while e != 0 {
            if let pct = (prop(e, "BatteryPercent") as? NSNumber)?.intValue, (0...100).contains(pct) {
                let name = (prop(e, "Product") as? String) ?? (prop(e, "DeviceName") as? String) ?? ""
                if !name.isEmpty {
                    let usage = (prop(e, "PrimaryUsage") as? NSNumber)?.intValue
                    let hint = name + (usage == 6 ? " keyboard" : usage == 2 ? " mouse" : "")
                    let addr = (prop(e, "DeviceAddress") as? String) ?? name
                    let status = (prop(e, "BatteryStatusFlags") as? NSNumber)?.intValue ?? 0
                    rows[addr] = BatteryRow(id: "io-" + addr, name: name, symbol: symbol(for: hint), percent: pct,
                                            charging: status & 0x1 != 0 && (prop(e, "Transport") as? String) == "USB",
                                            detail: nil)
                }
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        return Array(rows.values)
    }

    /// Merge by device name (case-insensitive); earlier lists win.
    static func merge(_ lists: [[BatteryRow]]) -> [BatteryRow] {
        var seen = Set<String>(), out: [BatteryRow] = []
        for r in lists.joined() where seen.insert(r.name.lowercased()).inserted { out.append(r) }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Standard BLE Battery Service (0x180F / 0x2A19): covers third-party keyboards and mice (Logitech, Keychron…)
/// that macOS does not list anywhere else. Needs the Bluetooth permission.
final class GattBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let service = CBUUID(string: "180F"), level = CBUUID(string: "2A19")
    private var central: CBCentralManager!
    private var peripherals: [CBPeripheral] = []
    private var done = Set<UUID>()
    private var rows: [BatteryRow] = []
    private var completion: (([BatteryRow]) -> Void)?
    private var waitingForPower = false
    private var generation = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// Main thread only. Always calls `done` (empty on failure / timeout).
    func read(_ finished: @escaping ([BatteryRow]) -> Void) {
        guard completion == nil else { finished([]); return }
        completion = finished
        rows = []; done = []; peripherals = []; generation += 1
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if let self, self.generation == g, self.completion != nil { self.finish() }
        }
        switch central.state {
        case .poweredOn: start()
        case .unknown, .resetting: waitingForPower = true
        default: finish()
        }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard completion != nil, waitingForPower else { return }
        waitingForPower = false
        c.state == .poweredOn ? start() : finish()
    }

    private func start() {
        peripherals = central.retrieveConnectedPeripherals(withServices: [Self.service])
        if peripherals.isEmpty { finish(); return }
        for p in peripherals {
            p.delegate = self
            if p.state == .connected { p.discoverServices([Self.service]) } else { central.connect(p) }
        }
    }

    private func mark(_ p: CBPeripheral) {
        done.insert(p.identifier)
        if done.count >= peripherals.count { finish() }
    }

    private func finish() {
        for p in peripherals where p.state != .disconnected { central.cancelPeripheralConnection(p) }
        let r = rows, c = completion
        completion = nil; peripherals = []
        c?(r)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([Self.service]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { mark(p) }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { mark(p); return }
        p.discoverCharacteristics([Self.level], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.level }) else { mark(p); return }
        p.readValue(for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let b = ch.value?.first, b <= 100 {
            let name = p.name ?? "Bluetooth"
            rows.append(BatteryRow(id: "gatt-" + p.identifier.uuidString, name: name,
                                   symbol: BatteryReader.symbol(for: name), percent: Int(b), charging: false, detail: nil))
        }
        mark(p)
    }
}

final class BatteryModel: ObservableObject {
    @Published var rows: [BatteryRow] = []
    private var timer: Timer?
    private var refreshing = false
    private lazy var gatt = GattBattery()

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let mac = BatteryReader.mac()
            let bt = BatteryReader.bluetooth()
            let io = BatteryReader.ioregistry()
            DispatchQueue.main.async {
                self.gatt.read { g in
                    self.rows = (mac.map { [$0] } ?? []) + BatteryReader.merge([bt, io, g])
                    self.refreshing = false
                }
            }
        }
    }
}
