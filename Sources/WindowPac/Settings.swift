import Cocoa

/// Modifier combination used for window snapping (default ⌘⌥).
/// Adding ⇧ on top of it triggers the "move to other display / full screen" variants.
enum SnapModifier: String, CaseIterable {
    case optCmd, ctrlOpt, ctrlCmd

    var flags: CGEventFlags {
        switch self {
        case .optCmd:  return [.maskAlternate, .maskCommand]
        case .ctrlOpt: return [.maskControl, .maskAlternate]
        case .ctrlCmd: return [.maskControl, .maskCommand]
        }
    }

    var title: String {
        switch self {
        case .optCmd:  return "⌘⌥ + Arrow"
        case .ctrlOpt: return "⌃⌥ + Arrow"
        case .ctrlCmd: return "⌃⌘ + Arrow"
        }
    }
}

enum Settings {
    private static let d = UserDefaults.standard

    static var snapModifier: SnapModifier {
        get { SnapModifier(rawValue: d.string(forKey: "snapModifierV2") ?? "") ?? .optCmd }
        set { d.set(newValue.rawValue, forKey: "snapModifierV2") }
    }
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
    /// True once we auto-registered the login item (so a user opt-out sticks).
    static var loginItemConfigured: Bool {
        get { d.bool(forKey: "loginItemConfigured") }
        set { d.set(newValue, forKey: "loginItemConfigured") }
    }
}
