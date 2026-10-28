import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = HotKeyController()
    private let battery = BatteryWidget()
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "WindowPac")
        rebuildMenu()

        // Ask for Accessibility once, then wait until it is granted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        monitor.reload()
        battery.apply()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        guard AXIsProcessTrusted() else { return }
        pollTimer?.invalidate(); pollTimer = nil
        // First run after Accessibility was granted: start at login from now on.
        if !Settings.loginItemConfigured {
            Settings.loginItemConfigured = true
            LoginItem.set(true)
        }
        rebuildMenu()
    }

    // MARK: Menu

    private func rebuildMenu() {
        let m = statusItem.menu ?? NSMenu()
        m.removeAllItems()
        m.delegate = self
        let ax = AXIsProcessTrusted()
        let state = NSMenuItem(title: ax ? "Active" : "Waiting for Accessibility permission…", action: nil, keyEquivalent: "")
        state.isEnabled = false
        m.addItem(state)
        let hk = monitor.failed.isEmpty ? "Hotkeys: ✓ registered" : "Hotkeys: ✗ unavailable: " + monitor.failed.joined(separator: ", ")
        for line in ["Accessibility: \(ax ? "✓" : "✗ missing")", hk,
                     "Last snap: \(monitor.lastResult.isEmpty ? "-" : monitor.lastResult)"] {
            let it = NSMenuItem(title: line, action: nil, keyEquivalent: ""); it.isEnabled = false
            m.addItem(it)
        }
        if !ax {
            m.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        m.addItem(.separator())

        let snap = NSMenuItem(title: "Window snapping", action: #selector(toggleSnap), keyEquivalent: "")
        snap.state = Settings.snapEnabled ? .on : .off; snap.target = self
        m.addItem(snap)

        let sub = NSMenu()
        for mod in SnapModifier.allCases {
            let it = NSMenuItem(title: mod.title, action: #selector(pickModifier(_:)), keyEquivalent: "")
            it.representedObject = mod.rawValue; it.target = self
            it.state = Settings.snapModifier == mod ? .on : .off
            sub.addItem(it)
        }
        let subItem = NSMenuItem(title: "Snap shortcut", action: nil, keyEquivalent: "")
        subItem.submenu = sub
        m.addItem(subItem)

        let sw = NSMenuItem(title: "Alt-Tab window switcher (⌥⇥)", action: #selector(toggleSwitcher), keyEquivalent: "")
        sw.state = Settings.switcherEnabled ? .on : .off; sw.target = self
        m.addItem(sw)

        let wl = NSMenuItem(title: "Alt-Tab: include apps without windows", action: #selector(toggleWindowless), keyEquivalent: "")
        wl.state = Settings.showWindowlessApps ? .on : .off; wl.target = self
        m.addItem(wl)

        let bw = NSMenuItem(title: "Desktop battery widget", action: #selector(toggleBattery), keyEquivalent: "")
        bw.state = Settings.batteryWidgetEnabled ? .on : .off; bw.target = self
        m.addItem(bw)

        m.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isEnabled ? .on : .off; login.target = self
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit WindowPac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Re-evaluate on every open so the status lines are current.
        if !monitor.isRunning, AXIsProcessTrusted() { tick() }
        if menu.items.isEmpty { return }
        rebuildMenu()
    }

    @objc private func toggleSnap() { Settings.snapEnabled.toggle(); monitor.reload(); rebuildMenu() }
    @objc private func toggleSwitcher() { Settings.switcherEnabled.toggle(); monitor.reload(); rebuildMenu() }
    @objc private func toggleWindowless() { Settings.showWindowlessApps.toggle(); rebuildMenu() }
    @objc private func toggleBattery() { Settings.batteryWidgetEnabled.toggle(); battery.apply(); rebuildMenu() }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled); rebuildMenu() }
    @objc private func pickModifier(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let m = SnapModifier(rawValue: raw) { Settings.snapModifier = m; monitor.reload() }
        rebuildMenu()
    }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
