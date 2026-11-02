import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let clipboardPanel = ClipboardPanel()
    private let menuBar = MenuBarManager()
    private lazy var monitor = HotKeyController(clipboard: clipboardPanel, menuBar: menuBar)
    private let battery = BatteryWidget()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "wp_main"
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "WindowPac")
        rebuildMenu()

        // Ask for Accessibility once, then wait until it is granted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        applySettings()
        let nc = NotificationCenter.default
        nc.addObserver(forName: .windowPacSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.applySettings() }
        nc.addObserver(forName: .windowPacRecording, object: nil, queue: .main) { [weak self] n in
            // Release the global hotkeys while a new combination is being recorded.
            if (n.userInfo?["on"] as? Bool) == true { self?.monitor.suspend() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func applySettings() {
        monitor.reload()
        battery.apply()
        ClipboardStore.shared.apply()
        menuBar.apply()
        rebuildMenu()
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

        let sw = NSMenuItem(title: "Alt-Tab window switcher (\(ShortcutStore.get(.switcherNext).display))",
                            action: #selector(toggleSwitcher), keyEquivalent: "")
        sw.state = Settings.switcherEnabled ? .on : .off; sw.target = self
        m.addItem(sw)

        let wl = NSMenuItem(title: "Alt-Tab: include apps without windows", action: #selector(toggleWindowless), keyEquivalent: "")
        wl.state = Settings.showWindowlessApps ? .on : .off; wl.target = self
        m.addItem(wl)

        let bw = NSMenuItem(title: "Desktop battery widget", action: #selector(toggleBattery), keyEquivalent: "")
        bw.state = Settings.batteryWidgetEnabled ? .on : .off; bw.target = self
        m.addItem(bw)

        if Settings.menuBarEnabled {
            let mb = NSMenuItem(title: menuBar.collapsed ? "Show hidden menu bar icons" : "Hide menu bar icons (left of |)",
                                action: #selector(toggleMenuBar), keyEquivalent: "")
            mb.target = self
            m.addItem(mb)
        }

        if Settings.menuBarEnabled {
            let dbg = NSMenuItem(title: "Debug: menu bar layout…", action: #selector(showMenuBarLayout), keyEquivalent: "")
            dbg.target = self
            m.addItem(dbg)
        }

        let cb = NSMenuItem(title: "Clipboard history (\(ShortcutStore.get(.clipboard).display))",
                            action: #selector(toggleClipboard), keyEquivalent: "")
        cb.state = Settings.clipboardEnabled ? .on : .off; cb.target = self
        m.addItem(cb)
        let show = NSMenuItem(title: "Show clipboard history…", action: #selector(showClipboard), keyEquivalent: "")
        show.target = self
        m.addItem(show)

        m.addItem(.separator())
        let st = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        st.target = self
        m.addItem(st)
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

    @objc private func toggleSnap() { Settings.snapEnabled.toggle(); applySettings() }
    @objc private func toggleSwitcher() { Settings.switcherEnabled.toggle(); applySettings() }
    @objc private func toggleWindowless() { Settings.showWindowlessApps.toggle(); rebuildMenu() }
    @objc private func toggleBattery() { Settings.batteryWidgetEnabled.toggle(); applySettings() }
    @objc private func toggleClipboard() { Settings.clipboardEnabled.toggle(); applySettings() }
    @objc private func showMenuBarLayout() {
        let a = NSAlert()
        a.messageText = "Menu bar layout"
        a.informativeText = menuBar.layoutReport()
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Test collapse 10000")
        a.addButton(withTitle: "Test collapse 3000")
        a.addButton(withTitle: "Test collapse 1200")
        a.addButton(withTitle: "Expand")
        NSApp.activate(ignoringOtherApps: true)
        let lengths: [CGFloat?] = [nil, 10_000, 3_000, 1_200, nil]
        let i = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard i > 0, i < lengths.count else { return }
        menuBar.debugCollapse(length: lengths[i])
        // Show the new state for a moment, then report it again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showMenuBarLayout() }
    }
    @objc private func toggleMenuBar() { menuBar.toggle(); rebuildMenu() }
    @objc private func showClipboard() { clipboardPanel.toggle() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled); rebuildMenu() }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
