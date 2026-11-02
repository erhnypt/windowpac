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
    static var clipboardImages: Bool {
        get { d.object(forKey: "clipboardImages") as? Bool ?? true }
        set { d.set(newValue, forKey: "clipboardImages") }
    }
    static var clipboardFiles: Bool {
        get { d.object(forKey: "clipboardFiles") as? Bool ?? true }
        set { d.set(newValue, forKey: "clipboardFiles") }
    }
    /// Bundle IDs of apps whose copies are never recorded (password managers by default).
    static let defaultIgnoredApps = ["com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
                                     "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.apple.keychainaccess",
                                     "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal"]
    static var clipboardIgnoredApps: [String] {
        get { d.stringArray(forKey: "clipboardIgnoredApps") ?? defaultIgnoredApps }
        set { d.set(newValue, forKey: "clipboardIgnoredApps") }
    }
    static var clipboardMax: Int {
        get { min(max(d.object(forKey: "clipboardMax") as? Int ?? 50, 10), 200) }
        set { d.set(newValue, forKey: "clipboardMax") }
    }
    /// Menu bar icon manager (‹ › toggle, hidden zone, dividers).
    static var menuBarEnabled: Bool {
        get { d.object(forKey: "menuBarEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "menuBarEnabled") }
    }
    /// Bundle IDs of apps whose menu bar icon is hidden (covered) and listed in the drop-down card instead.
    static var menuBarHiddenApps: [String] {
        get { d.stringArray(forKey: "menuBarHiddenApps") ?? [] }
        set { d.set(newValue, forKey: "menuBarHiddenApps") }
    }
    static var language: AppLanguage {
        get { AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "language") }
    }
    /// True once we auto-registered the login item (so a user opt-out sticks).
    static var loginItemConfigured: Bool {
        get { d.bool(forKey: "loginItemConfigured") }
        set { d.set(newValue, forKey: "loginItemConfigured") }
    }
}
