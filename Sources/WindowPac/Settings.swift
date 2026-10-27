import Cocoa

/// Modifier combination used for window snapping. Adding ⇧ on top of it
/// triggers the "move to other display / full screen" variants.
enum SnapModifier: String, CaseIterable {
    case ctrlOpt, ctrlCmd, optCmd

    var flags: CGEventFlags {
        switch self {
        case .ctrlOpt: return [.maskControl, .maskAlternate]
        case .ctrlCmd: return [.maskControl, .maskCommand]
        case .optCmd:  return [.maskAlternate, .maskCommand]
        }
    }

    var title: String {
        switch self {
        case .ctrlOpt: return "⌃⌥ + Arrow"
        case .ctrlCmd: return "⌃⌘ + Arrow"
        case .optCmd:  return "⌥⌘ + Arrow"
        }
    }
}

enum Settings {
    private static let d = UserDefaults.standard

    static var snapModifier: SnapModifier {
        get { SnapModifier(rawValue: d.string(forKey: "snapModifier") ?? "") ?? .ctrlOpt }
        set { d.set(newValue.rawValue, forKey: "snapModifier") }
    }
    static var snapEnabled: Bool {
        get { d.object(forKey: "snapEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "snapEnabled") }
    }
    static var switcherEnabled: Bool {
        get { d.object(forKey: "switcherEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "switcherEnabled") }
    }
    /// True once we auto-registered the login item (so a user opt-out sticks).
    static var loginItemConfigured: Bool {
        get { d.bool(forKey: "loginItemConfigured") }
        set { d.set(newValue, forKey: "loginItemConfigured") }
    }
}
