import Cocoa
import ApplicationServices

/// Global keyboard hook (CGEventTap). Needs the Accessibility permission.
final class HotKeyMonitor {
    private var tap: CFMachPort?
    private let switcher = Switcher()

    private enum Key {
        static let tab: Int64 = 48, esc: Int64 = 53
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    }
    private let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    var isRunning: Bool { tap != nil }
    /// Last key-down seen by the tap, shown in the menu for troubleshooting.
    private(set) var lastSeen = "none yet"
    private(set) var lastResult = ""

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                        callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .flagsChanged:
            if switcher.isActive, !event.flags.contains(.maskAlternate) {
                DispatchQueue.main.async { self.switcher.commit() }
            }
            return pass

        case .keyUp:
            // Swallow the Tab key-up that belongs to a swallowed key-down.
            if switcher.isActive, event.getIntegerValueField(.keyboardEventKeycode) == Key.tab { return nil }
            return pass

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let mods = event.flags.intersection(relevant)
            if !mods.isEmpty {
                lastSeen = "key \(key) flags \(mods.rawValue >> 16) (⌥ ⇒ 8, ⌃ ⇒ 4, ⇧ ⇒ 2, ⌘ ⇒ 16)"
            }

            // ---- Alt-Tab switcher (⌥⇥ / ⌥⇧⇥) ----
            if switcher.isActive {
                switch key {
                case Key.tab:
                    DispatchQueue.main.async { self.switcher.advance(backwards: mods.contains(.maskShift)) }
                    return nil
                case Key.right, Key.down:
                    DispatchQueue.main.async { self.switcher.advance(backwards: false) }
                    return nil
                case Key.left, Key.up:
                    DispatchQueue.main.async { self.switcher.advance(backwards: true) }
                    return nil
                case Key.esc:
                    DispatchQueue.main.async { self.switcher.cancel() }
                    return nil
                default: return nil   // keep the session modal while ⌥ is held
                }
            }
            if Settings.switcherEnabled, key == Key.tab,
               mods == [.maskAlternate] || mods == [.maskAlternate, .maskShift] {
                let back = mods.contains(.maskShift)
                DispatchQueue.main.async { self.switcher.advance(backwards: back) }
                return nil
            }

            // ---- Window snapping ----
            if Settings.snapEnabled, [Key.left, Key.right, Key.up, Key.down].contains(key) {
                let base = Settings.snapModifier.flags
                let withShift = mods == base.union(.maskShift)
                guard mods == base || withShift else { return pass }
                let action: SnapAction
                switch (key, withShift) {
                case (Key.left, false):  action = .left
                case (Key.right, false): action = .right
                case (Key.up, false):    action = .maximize
                case (Key.down, false):  action = .restoreOrMinimize
                case (Key.left, true):   action = .moveDisplayLeft
                case (Key.right, true):  action = .moveDisplayRight
                case (Key.up, true):     action = .enterFullScreen
                default:                 action = .exitFullScreen
                }
                DispatchQueue.main.async { self.lastResult = WindowManager.perform(action) }
                return nil
            }
            return pass

        default:
            return pass
        }
    }
}
