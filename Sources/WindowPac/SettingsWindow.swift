import Cocoa
import SwiftUI
import UniformTypeIdentifiers

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

/// Snippets (named notes kept in the clipboard panel) and the list of apps whose copies are ignored.
private struct ClipboardSettingsView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var editingID: UUID?
    @State private var title = ""
    @State private var text = ""
    @State private var apps = Settings.clipboardIgnoredApps

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func saveApps() { Settings.clipboardIgnoredApps = apps }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
        saveApps()
    }

    private func commit() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !text.isEmpty else { NSSound.beep(); return }
        if let id = editingID { store.updateSnippet(id: id, title: t, text: text) } else { store.addSnippet(title: t, text: text) }
        editingID = nil; title = ""; text = ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Snippets").font(.headline)
                Text("Named notes that always stay at the top of the clipboard panel and are never removed automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.snippets.isEmpty {
                    Text("No snippets yet").foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { sn in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sn.title ?? "").fontWeight(.medium)
                            Text(sn.text).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingID = sn.id; title = sn.title ?? ""; text = sn.text }
                        Button { store.deleteSnippet(sn.id); if editingID == sn.id { editingID = nil; title = ""; text = "" } }
                            label: { Image(systemName: "trash") }
                    }
                }
                TextField("Title", text: $title)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                HStack {
                    Button(editingID == nil ? "Add snippet" : "Save changes") { commit() }
                    if editingID != nil { Button("Cancel") { editingID = nil; title = ""; text = "" } }
                }
                Divider()
                Text("Ignored apps").font(.headline)
                Text("Anything copied while one of these apps is in front is not recorded.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(apps, id: \.self) { id in
                    HStack {
                        Text(appName(id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { apps.removeAll { $0 == id }; saveApps() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Add app…") { addApp() }
                    Button("Reset list") { apps = Settings.defaultIgnoredApps; saveApps() }
                }
            }
            .padding(8)
        }
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
            ClipboardSettingsView().tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
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
                Toggle("Record images", isOn: flag({ Settings.clipboardImages }, { Settings.clipboardImages = $0 }))
                Toggle("Record copied files (Finder)", isOn: flag({ Settings.clipboardFiles }, { Settings.clipboardFiles = $0 }))
                Toggle("Keep history after restart (stored on this Mac, owner-only)",
                       isOn: flag({ Settings.clipboardPersist }, { Settings.clipboardPersist = $0 }))
                Stepper("Items to keep: \(Settings.clipboardMax)",
                        value: Binding(get: { Settings.clipboardMax }, set: { Settings.clipboardMax = $0; refresh += 1; notifyChanged() }),
                        in: 10...200, step: 10)
                Button("Clear unpinned history") { ClipboardStore.shared.clear() }
                Text("Pinned items are never removed and always saved. Passwords copied from password managers are not recorded.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Hide / show menu bar icons (‹ ›)", isOn: flag({ Settings.menuBarEnabled }, { Settings.menuBarEnabled = $0 }))
                Stepper("Dividers ( | ): \(Settings.menuBarDividers)",
                        value: Binding(get: { Settings.menuBarDividers }, set: { Settings.menuBarDividers = $0; refresh += 1; notifyChanged() }),
                        in: 0...3)
                Picker("Hide again after", selection: Binding(get: { Settings.menuBarAutoHide },
                                                              set: { Settings.menuBarAutoHide = $0; refresh += 1; notifyChanged() })) {
                    Text("Never").tag(0); Text("5 seconds").tag(5); Text("10 seconds").tag(10); Text("30 seconds").tag(30)
                }
                Text("Show the icons with ›, then hold ⌘ and drag an icon to the left of the | separator to hide it, or to the right to keep it visible. Hiding covers those icons with a copy of the menu bar background (needs Screen Recording permission). Extra dividers split the visible area into blocks.")
                    .font(.caption).foregroundStyle(.secondary)
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
