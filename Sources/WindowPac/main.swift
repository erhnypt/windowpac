import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = HotKeyMonitor()
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "WindowPac")
        rebuildMenu()

        // Ask for Accessibility once, then wait until it is granted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        // Keyboard event taps also need "Input Monitoring" on modern macOS.
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        guard AXIsProcessTrusted(), monitor.start() else {
            if !AXIsProcessTrusted() { NSLog("WindowPac: waiting for Accessibility") }
            else { NSLog("WindowPac: event tap failed (Input Monitoring missing?)") }
            return
        }
        pollTimer?.invalidate(); pollTimer = nil
        // First successful run after the permission was granted: start at login from now on.
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
        let state = NSMenuItem(title: monitor.isRunning ? "Active" : "Waiting for permissions (Accessibility + Input Monitoring)…",
                               action: nil, keyEquivalent: "")
        state.isEnabled = false
        m.addItem(state)
        let ax = AXIsProcessTrusted(), im = CGPreflightListenEventAccess()
        for line in ["Accessibility: \(ax ? "✓" : "✗ missing")",
                     "Input Monitoring: \(im ? "✓" : "✗ missing")",
                     "Keyboard hook: \(monitor.isRunning ? "✓ running" : "✗ not running")",
                     "Last key: \(monitor.lastSeen)",
                     "Last snap: \(monitor.lastResult.isEmpty ? "-" : monitor.lastResult)"] {
            let it = NSMenuItem(title: line, action: nil, keyEquivalent: ""); it.isEnabled = false
            m.addItem(it)
        }
        if !monitor.isRunning {
            m.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "").target = self
            m.addItem(withTitle: "Open Input Monitoring Settings", action: #selector(openInputMonitoring), keyEquivalent: "").target = self
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

        let dbg = NSMenu()
        for (title, mode) in [("Off (no key hook)", HotKeyMonitor.Mode.off),
                              ("Listen only (shortcuts won't act)", .listenOnly),
                              ("Active", .active)] {
            let it = NSMenuItem(title: title, action: #selector(pickHookMode(_:)), keyEquivalent: "")
            it.representedObject = mode.rawValue; it.target = self
            it.state = monitor.mode == mode ? .on : .off
            dbg.addItem(it)
        }
        let dbgItem = NSMenuItem(title: "Debug: keyboard hook mode", action: nil, keyEquivalent: "")
        dbgItem.submenu = dbg
        m.addItem(dbgItem)

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
        if !monitor.isRunning { tick() }
        if menu.items.isEmpty { return }
        rebuildMenu()
    }

    @objc private func pickHookMode(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let m = HotKeyMonitor.Mode(rawValue: raw) { monitor.setMode(m) }
        rebuildMenu()
    }

    @objc private func toggleSnap() { Settings.snapEnabled.toggle(); rebuildMenu() }
    @objc private func toggleSwitcher() { Settings.switcherEnabled.toggle(); rebuildMenu() }
    @objc private func toggleWindowless() { Settings.showWindowlessApps.toggle(); rebuildMenu() }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled); rebuildMenu() }
    @objc private func pickModifier(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let m = SnapModifier(rawValue: raw) { Settings.snapModifier = m }
        rebuildMenu()
    }
    @objc private func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
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
