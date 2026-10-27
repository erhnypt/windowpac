import Cocoa
import Carbon.HIToolbox

/// Thin wrapper over Carbon's RegisterEventHotKey. Unlike a CGEventTap it never sees ordinary
/// key presses (a keyboard event tap breaks plain Tab in some apps) and needs no Input Monitoring.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    func register(key: Int, mods: UInt32, handler: @escaping () -> Void) -> UInt32? {
        install()
        var ref: EventHotKeyRef?
        let id = nextID; nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x57504143), id: id)   // 'WPAC'
        guard RegisterEventHotKey(UInt32(key), mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return nil }
        refs[id] = ref; handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        handlers[id] = nil
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            HotKeyCenter.shared.handlers[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Registers the snapping shortcuts and the Alt-Tab switcher shortcuts.
final class HotKeyController {
    private let center = HotKeyCenter.shared
    private let switcher = Switcher()
    private var fixedIDs: [UInt32] = []
    private var sessionIDs: [UInt32] = []
    private var timer: Timer?
    private(set) var failed: [String] = []
    private(set) var lastResult = ""

    var isRunning: Bool { !fixedIDs.isEmpty }

    private enum K { static let tab = 48, esc = 53, left = 123, right = 124, down = 125, up = 126 }
    private let opt = UInt32(optionKey), shift = UInt32(shiftKey)

    private func carbon(_ f: CGEventFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.maskCommand) { m |= UInt32(cmdKey) }
        if f.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if f.contains(.maskControl) { m |= UInt32(controlKey) }
        return m
    }

    /// (Re)registers everything according to the current settings.
    func reload() {
        endSession(commit: false)
        fixedIDs.forEach(center.unregister); fixedIDs = []
        failed = []

        func add(_ name: String, _ key: Int, _ mods: UInt32, _ h: @escaping () -> Void) {
            if let id = center.register(key: key, mods: mods, handler: h) { fixedIDs.append(id) }
            else { failed.append(name) }
        }

        if Settings.snapEnabled {
            let base = carbon(Settings.snapModifier.flags)
            let table: [(String, Int, SnapAction, SnapAction)] = [
                ("←", K.left, .left, .moveDisplayLeft), ("→", K.right, .right, .moveDisplayRight),
                ("↑", K.up, .maximize, .enterFullScreen), ("↓", K.down, .restoreOrMinimize, .exitFullScreen)]
            for (n, key, plain, shifted) in table {
                add("snap \(n)", key, base) { [unowned self] in self.lastResult = WindowManager.perform(plain) }
                add("snap ⇧\(n)", key, base | shift) { [unowned self] in self.lastResult = WindowManager.perform(shifted) }
            }
        }
        if Settings.switcherEnabled {
            add("⌥⇥", K.tab, opt) { [unowned self] in self.advance(backwards: false) }
            add("⌥⇧⇥", K.tab, opt | shift) { [unowned self] in self.advance(backwards: true) }
        }
    }

    // MARK: Alt-Tab session

    private func advance(backwards: Bool) {
        switcher.advance(backwards: backwards)
        if switcher.isActive, timer == nil { beginSession() }
    }

    private func beginSession() {
        // While ⌥ is held the arrows / Esc steer the switcher.
        func add(_ key: Int, _ h: @escaping () -> Void) {
            if let id = center.register(key: key, mods: opt, handler: h) { sessionIDs.append(id) }
        }
        add(K.right) { [unowned self] in self.switcher.advance(backwards: false) }
        add(K.down)  { [unowned self] in self.switcher.advance(backwards: false) }
        add(K.left)  { [unowned self] in self.switcher.advance(backwards: true) }
        add(K.up)    { [unowned self] in self.switcher.advance(backwards: true) }
        add(K.esc)   { [unowned self] in self.endSession(commit: false) }

        // Releasing ⌥ commits. Polled: reading the modifier state needs no permission.
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [unowned self] _ in
            if !NSEvent.modifierFlags.contains(.option) { self.endSession(commit: true) }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func endSession(commit: Bool) {
        timer?.invalidate(); timer = nil
        sessionIDs.forEach(center.unregister); sessionIDs = []
        guard switcher.isActive else { return }
        commit ? switcher.commit() : switcher.cancel()
    }
}
