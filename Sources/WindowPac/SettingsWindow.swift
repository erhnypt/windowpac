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
            Button(recording ? L.t("Press keys…") : shortcut.display) { recording ? stop() : start() }
                .frame(minWidth: 110)
            Button { ShortcutStore.reset(action); shortcut = ShortcutStore.get(action); message = ""; notifyChanged() }
                label: { Image(systemName: "arrow.counterclockwise") }
                .help(L.t("Reset to default"))
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
                message = L.t("Use ⌘, ⌥ or ⌃"); NSSound.beep(); return nil
            }
            if let other = ShortcutStore.conflict(sc, except: action) {
                message = L.f("Used by “%@”", other.title); NSSound.beep(); return nil
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
                Text(L.t("Snippets")).font(.headline)
                Text(L.t("Named notes that always stay at the top of the clipboard panel and are never removed automatically."))
                    .font(.caption).foregroundStyle(.secondary)
                if store.snippets.isEmpty {
                    Text(L.t("No snippets yet")).foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { sn in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sn.title ?? "").fontWeight(.medium)
                            Text(sn.text).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L.t("Edit")) { editingID = sn.id; title = sn.title ?? ""; text = sn.text }
                        Button { store.deleteSnippet(sn.id); if editingID == sn.id { editingID = nil; title = ""; text = "" } }
                            label: { Image(systemName: "trash") }
                    }
                }
                TextField(L.t("Title"), text: $title)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                HStack {
                    Button(editingID == nil ? "Add snippet" : "Save changes") { commit() }
                    if editingID != nil { Button(L.t("Cancel")) { editingID = nil; title = ""; text = "" } }
                }
                Divider()
                Text(L.t("Ignored apps")).font(.headline)
                Text(L.t("Anything copied while one of these apps is in front is not recorded."))
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
                    Button(L.t("Add app…")) { addApp() }
                    Button(L.t("Reset list")) { apps = Settings.defaultIgnoredApps; saveApps() }
                }
            }
            .padding(8)
        }
    }
}

/// Choose which apps' menu bar icons are hidden (they move into the drop-down card).
private struct MenuBarSettingsView: View {
    private struct Row: Identifiable { let id: String; let name: String; let icon: NSImage?; let running: Bool }

    @State private var hidden = Settings.menuBarHiddenApps
    @State private var enabled = Settings.menuBarEnabled
    @State private var rows: [Row] = []
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private func reload() {
        var seen = Set<String>()
        var list: [Row] = []
        for w in StatusBar.windows() {
            guard let id = StatusBar.bundleID(of: w.pid), seen.insert(id).inserted else { continue }
            let app = NSRunningApplication(processIdentifier: w.pid)
            list.append(Row(id: id, name: app?.localizedName ?? w.owner, icon: app?.icon, running: true))
        }
        // Apps that are hidden but not running right now stay in the list so they can be un-hidden.
        for id in hidden where !seen.contains(id) {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            list.append(Row(id: id, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }, running: false))
        }
        rows = list
    }

    private func set(_ id: String, hidden on: Bool) {
        if on, !hidden.contains(id) { hidden.append(id) }
        if !on { hidden.removeAll { $0 == id } }
        Settings.menuBarHiddenApps = hidden
        notifyChanged()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L.t("Hidden menu bar items (⌄ button)"), isOn: Binding(get: { enabled },
                    set: { enabled = $0; Settings.menuBarEnabled = $0; notifyChanged() }))
                Text(L.t("Turn on “Hide” for an app: its menu bar icon is covered with the menu bar background and moves into the card that drops down from the ⌄ button. Click it there to open its menu. Needs the Screen Recording permission to match the background; the gap where the icon was stays."))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(L.t("Apps with a menu bar icon")).font(.headline)
                if rows.isEmpty { Text(L.t("No other apps have a menu bar icon right now.")).foregroundStyle(.secondary) }
                ForEach(rows) { r in
                    HStack {
                        if let ic = r.icon { Image(nsImage: ic).resizable().frame(width: 22, height: 22) }
                        Text(r.name)
                        if !r.running { Text(L.t("not running")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Toggle(L.t("Hide"), isOn: Binding(get: { hidden.contains(r.id) }, set: { set(r.id, hidden: $0) }))
                    }
                }
                Text(L.t("Apple's own items (Wi-Fi, battery, clock…) can't be hidden here; manage them in System Settings → Control Center."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .onAppear { reload() }
        .onReceive(tick) { _ in reload() }
    }
}

private struct SettingsView: View {
    @State private var refresh = 0
    @State private var tab = 0

    private func flag(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { set($0); refresh += 1; notifyChanged() })
    }

    var body: some View {
        TabView(selection: $tab) {
            shortcuts.tabItem { Label(L.t("Shortcuts"), systemImage: "keyboard") }.tag(0)
            features.tabItem { Label(L.t("Features"), systemImage: "switch.2") }.tag(1)
            MenuBarSettingsView().tabItem { Label(L.t("Menu bar"), systemImage: "menubar.rectangle") }.tag(2)
            ClipboardSettingsView().tabItem { Label(L.t("Clipboard"), systemImage: "doc.on.clipboard") }.tag(3)
        }
        .id(Settings.language.rawValue)   // rebuild every tab when the language changes
        .padding(16)
        .frame(width: 560, height: 560)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ShortcutAction.Group.allCases, id: \.rawValue) { g in
                    Text(g.title).font(.headline)
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
                    Text(L.t("Shortcuts need ⌘, ⌥ or ⌃. Esc cancels recording.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("Reset all")) { ShortcutStore.resetAll(); refresh += 1; notifyChanged() }
                }
            }
            .padding(8)
        }
        .id(refresh)   // lets "Reset all" reload the recorders
    }

    private var features: some View {
        Form {
            Section(L.t("Language")) {
                Picker(L.t("Language"), selection: Binding(get: { Settings.language },
                                                           set: { Settings.language = $0; refresh += 1; notifyChanged() })) {
                    Text(L.t("Automatic")).tag(AppLanguage.auto)
                    Text("English").tag(AppLanguage.en)
                    Text("Türkçe").tag(AppLanguage.tr)
                }
            }
            Section(L.t("Windows")) {
                Toggle(L.t("Window snapping"), isOn: flag({ Settings.snapEnabled }, { Settings.snapEnabled = $0 }))
                Toggle(L.t("Alt-Tab window switcher"), isOn: flag({ Settings.switcherEnabled }, { Settings.switcherEnabled = $0 }))
                Toggle(L.t("Alt-Tab: include apps without windows"),
                       isOn: flag({ Settings.showWindowlessApps }, { Settings.showWindowlessApps = $0 }))
            }
            Section(L.t("Clipboard history")) {
                Toggle(L.t("Record copied text"), isOn: flag({ Settings.clipboardEnabled }, { Settings.clipboardEnabled = $0 }))
                Toggle(L.t("Record images"), isOn: flag({ Settings.clipboardImages }, { Settings.clipboardImages = $0 }))
                Toggle(L.t("Record copied files (Finder)"), isOn: flag({ Settings.clipboardFiles }, { Settings.clipboardFiles = $0 }))
                Toggle(L.t("Keep history after restart (stored on this Mac, owner-only)"),
                       isOn: flag({ Settings.clipboardPersist }, { Settings.clipboardPersist = $0 }))
                Stepper(L.f("Items to keep: %d", Settings.clipboardMax),
                        value: Binding(get: { Settings.clipboardMax }, set: { Settings.clipboardMax = $0; refresh += 1; notifyChanged() }),
                        in: 10...200, step: 10)
                Button(L.t("Clear unpinned history")) { ClipboardStore.shared.clear() }
                Text(L.t("Pinned items are never removed and always saved. Passwords copied from password managers are not recorded.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Other")) {
                Toggle(L.t("Desktop battery widget"), isOn: flag({ Settings.batteryWidgetEnabled }, { Settings.batteryWidgetEnabled = $0 }))
                Toggle(L.t("Launch at login"), isOn: flag({ LoginItem.isEnabled }, { LoginItem.set($0) }))
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
                        w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = L.t("WindowPac Settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
