import Cocoa
import SwiftUI

private func notifyChanged() {
    NotificationCenter.default.post(name: .windowPacSettingsChanged, object: nil)
}

/// Click, then press the new combination. Needs ⌘, ⌥ or ⌃. Esc cancels.
private struct ShortcutRecorder: View {
    let action: ShortcutAction
    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var message = ""
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: ShortcutStore.get(action))
    }

    var body: some View {
        HStack(spacing: 8) {
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
            Button(recording ? "Press keys…" : shortcut.display) { recording ? stop() : start() }
                .frame(minWidth: 110)
            Button { ShortcutStore.reset(action); shortcut = ShortcutStore.get(action); message = ""; notifyChanged() }
                label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset to default")
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = ""
        recording = true
        NotificationCenter.default.post(name: .windowPacRecording, object: nil, userInfo: ["on": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            guard let sc = Shortcut.from(event: e) else {
                message = "Use ⌘, ⌥ or ⌃"; NSSound.beep(); return nil
            }
            if let other = ShortcutStore.conflict(sc, except: action) {
                message = "Used by “\(other.title)”"; NSSound.beep(); return nil
            }
            ShortcutStore.set(action, sc)
            shortcut = sc
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        NotificationCenter.default.post(name: .windowPacRecording, object: nil, userInfo: ["on": false])
        notifyChanged()
    }
}

private struct SettingsView: View {
    @State private var refresh = 0

    private func flag(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { set($0); refresh += 1; notifyChanged() })
    }

    var body: some View {
        TabView {
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            features.tabItem { Label("Features", systemImage: "switch.2") }
        }
        .padding(16)
        .frame(width: 560, height: 560)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ShortcutAction.Group.allCases, id: \.rawValue) { g in
                    Text(g.rawValue).font(.headline)
                    ForEach(ShortcutAction.allCases.filter { $0.group == g }) { a in
                        HStack {
                            Text(a.title)
                            Spacer()
                            ShortcutRecorder(action: a)
                        }
                    }
                    Divider()
                }
                HStack {
                    Text("Shortcuts need ⌘, ⌥ or ⌃. Esc cancels recording.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset all") { ShortcutStore.resetAll(); refresh += 1; notifyChanged() }
                }
            }
            .padding(8)
        }
        .id(refresh)   // lets "Reset all" reload the recorders
    }

    private var features: some View {
        Form {
            Section("Windows") {
                Toggle("Window snapping", isOn: flag({ Settings.snapEnabled }, { Settings.snapEnabled = $0 }))
                Toggle("Alt-Tab window switcher", isOn: flag({ Settings.switcherEnabled }, { Settings.switcherEnabled = $0 }))
                Toggle("Alt-Tab: include apps without windows",
                       isOn: flag({ Settings.showWindowlessApps }, { Settings.showWindowlessApps = $0 }))
            }
            Section("Clipboard history") {
                Toggle("Record copied text", isOn: flag({ Settings.clipboardEnabled }, { Settings.clipboardEnabled = $0 }))
                Toggle("Keep history after restart (stored on this Mac, owner-only)",
                       isOn: flag({ Settings.clipboardPersist }, { Settings.clipboardPersist = $0 }))
                Stepper("Items to keep: \(Settings.clipboardMax)",
                        value: Binding(get: { Settings.clipboardMax }, set: { Settings.clipboardMax = $0; refresh += 1; notifyChanged() }),
                        in: 10...200, step: 10)
                Button("Clear history") { ClipboardStore.shared.clear() }
                Text("Passwords copied from password managers are not recorded.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Other") {
                Toggle("Desktop battery widget", isOn: flag({ Settings.batteryWidgetEnabled }, { Settings.batteryWidgetEnabled = $0 }))
                Toggle("Launch at login", isOn: flag({ LoginItem.isEnabled }, { LoginItem.set($0) }))
            }
        }
        .formStyle(.grouped)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "WindowPac Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
