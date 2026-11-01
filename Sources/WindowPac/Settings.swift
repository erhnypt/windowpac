import Cocoa

enum Settings {
    private static let d = UserDefaults.standard

    static var snapEnabled: Bool {
        get { d.object(forKey: "snapEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "snapEnabled") }
    }
    static var switcherEnabled: Bool {
        get { d.object(forKey: "switcherEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "switcherEnabled") }
    }
    /// Also list running apps that have no window (closed with ⌘W, not quit with ⌘Q).
    static var showWindowlessApps: Bool {
        get { d.bool(forKey: "showWindowlessApps") }
        set { d.set(newValue, forKey: "showWindowlessApps") }
    }
    static var batteryWidgetEnabled: Bool {
        get { d.object(forKey: "batteryWidgetEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "batteryWidgetEnabled") }
    }
    static var clipboardEnabled: Bool {
        get { d.object(forKey: "clipboardEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "clipboardEnabled") }
    }
    /// Keep the clipboard history on disk (~/Library/Application Support/WindowPac, owner-only) across restarts.
    static var clipboardPersist: Bool {
        get { d.object(forKey: "clipboardPersist") as? Bool ?? true }
        set { d.set(newValue, forKey: "clipboardPersist") }
    }
    static var clipboardMax: Int {
        get { min(max(d.object(forKey: "clipboardMax") as? Int ?? 50, 10), 200) }
        set { d.set(newValue, forKey: "clipboardMax") }
    }
    /// True once we auto-registered the login item (so a user opt-out sticks).
    static var loginItemConfigured: Bool {
        get { d.bool(forKey: "loginItemConfigured") }
        set { d.set(newValue, forKey: "loginItemConfigured") }
    }
}
