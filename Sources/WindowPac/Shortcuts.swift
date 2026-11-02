import Cocoa
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted after any setting / shortcut changed so everything re-applies it.
    static let windowPacSettingsChanged = Notification.Name("windowPacSettingsChanged")
    /// userInfo["on"]: Bool. While a shortcut is being recorded the global hotkeys are released.
    static let windowPacRecording = Notification.Name("windowPacRecording")
}

/// A global key combination. `mods` is a Carbon modifier mask (cmdKey, optionKey, ...).
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var mods: UInt32
    var label: String

    var display: String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + label
    }

    /// Modifiers (⇧ excluded) that must stay held while an Alt-Tab style session runs.
    var holdFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if mods & UInt32(cmdKey) != 0 { f.insert(.command) }
        if mods & UInt32(optionKey) != 0 { f.insert(.option) }
        if mods & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }
    /// The held modifiers as symbols, e.g. "⌥".
    var holdDisplay: String {
        var t = ""
        if mods & UInt32(controlKey) != 0 { t += "⌃" }
        if mods & UInt32(optionKey) != 0 { t += "⌥" }
        if mods & UInt32(cmdKey) != 0 { t += "⌘" }
        return t
    }
    var holdCarbon: UInt32 { mods & ~UInt32(shiftKey) }

    private static let names: [Int: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 48: "⇥", 49: "Space", 36: "↩", 51: "⌫", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12"]

    /// nil unless the event has at least one of ⌘ ⌥ ⌃ (⇧ alone would break typing).
    static func from(event e: NSEvent) -> Shortcut? {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        guard m != 0 else { return nil }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        let code = Int(e.keyCode)
        let label = names[code] ?? (e.charactersIgnoringModifiers?.uppercased() ?? "?")
        return Shortcut(keyCode: code, mods: m, label: label)
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case snapLeft, snapRight, maximize, restore, moveDisplayLeft, moveDisplayRight, enterFullScreen, exitFullScreen
    case switcherNext, switcherPrevious
    case clipboard
    case menuBarToggle

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case windows = "Window snapping", switcher = "Alt-Tab switcher", clipboard = "Clipboard history", menuBar = "Menu bar"
        var title: String { L.t(rawValue) }
    }

    var group: Group {
        switch self {
        case .switcherNext, .switcherPrevious: return .switcher
        case .clipboard: return .clipboard
        case .menuBarToggle: return .menuBar
        default: return .windows
        }
    }

    var title: String {
        switch self {
        case .snapLeft: return L.t("Snap left")
        case .snapRight: return L.t("Snap right")
        case .maximize: return L.t("Fill screen")
        case .restore: return L.t("Restore size / minimize")
        case .moveDisplayLeft: return L.t("Move to previous display")
        case .moveDisplayRight: return L.t("Move to next display")
        case .enterFullScreen: return L.t("Enter full screen")
        case .exitFullScreen: return L.t("Exit full screen")
        case .switcherNext: return L.t("Next window (hold modifier, release to switch)")
        case .switcherPrevious: return L.t("Previous window")
        case .clipboard: return L.t("Show clipboard history")
        case .menuBarToggle: return L.t("Show hidden menu bar items")
        }
    }

    var isEnabled: Bool {
        switch group {
        case .windows: return Settings.snapEnabled
        case .switcher: return Settings.switcherEnabled
        case .clipboard: return Settings.clipboardEnabled
        case .menuBar: return Settings.menuBarEnabled
        }
    }

    var defaultShortcut: Shortcut {
        let co = UInt32(cmdKey | optionKey), sh = UInt32(shiftKey)
        switch self {
        case .snapLeft: return Shortcut(keyCode: 123, mods: co, label: "←")
        case .snapRight: return Shortcut(keyCode: 124, mods: co, label: "→")
        case .maximize: return Shortcut(keyCode: 126, mods: co, label: "↑")
        case .restore: return Shortcut(keyCode: 125, mods: co, label: "↓")
        case .moveDisplayLeft: return Shortcut(keyCode: 123, mods: co | sh, label: "←")
        case .moveDisplayRight: return Shortcut(keyCode: 124, mods: co | sh, label: "→")
        case .enterFullScreen: return Shortcut(keyCode: 126, mods: co | sh, label: "↑")
        case .exitFullScreen: return Shortcut(keyCode: 125, mods: co | sh, label: "↓")
        case .switcherNext: return Shortcut(keyCode: 48, mods: UInt32(optionKey), label: "⇥")
        case .switcherPrevious: return Shortcut(keyCode: 48, mods: UInt32(optionKey) | sh, label: "⇥")
        case .clipboard: return Shortcut(keyCode: 9, mods: UInt32(controlKey | cmdKey), label: "V")
        case .menuBarToggle: return Shortcut(keyCode: 11, mods: UInt32(controlKey | cmdKey), label: "B")
        }
    }
}

enum ShortcutStore {
    private static let key = "shortcuts.v3"

    private static func load() -> [String: Shortcut] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Shortcut].self, from: data) else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: Shortcut]) {
        if let data = try? JSONEncoder().encode(dict) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func get(_ a: ShortcutAction) -> Shortcut { load()[a.rawValue] ?? a.defaultShortcut }

    static func set(_ a: ShortcutAction, _ s: Shortcut) { var d = load(); d[a.rawValue] = s; save(d) }

    static func reset(_ a: ShortcutAction) { var d = load(); d[a.rawValue] = nil; save(d) }

    static func resetAll() { UserDefaults.standard.removeObject(forKey: key) }

    /// Another action already using this exact combination.
    static func conflict(_ s: Shortcut, except a: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != a && get($0).keyCode == s.keyCode && get($0).mods == s.mods }
    }
}
