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

/// Registers every configured shortcut and drives the Alt-Tab session.
final class HotKeyController {
    private let center = HotKeyCenter.shared
    private let switcher = Switcher()
    private let clipboard: ClipboardPanel
    private let menuBar: MenuBarManager
    private var fixedIDs: [UInt32] = []
    private var sessionIDs: [UInt32] = []
    private var timer: Timer?
    private var hold: NSEvent.ModifierFlags = []
    private(set) var failed: [String] = []
    private(set) var lastResult = ""

    var isRunning: Bool { !fixedIDs.isEmpty }

    private enum K { static let esc = 53, left = 123, right = 124, down = 125, up = 126 }

    init(clipboard: ClipboardPanel, menuBar: MenuBarManager) { self.clipboard = clipboard; self.menuBar = menuBar }

    /// Releases all global hotkeys (used while a new shortcut is being recorded).
    func suspend() {
        endSession(commit: false)
        fixedIDs.forEach(center.unregister); fixedIDs = []
    }

    /// (Re)registers everything according to the current settings.
    func reload() {
        suspend()
        failed = []
        for action in ShortcutAction.allCases where action.isEnabled {
            let sc = ShortcutStore.get(action)
            if let id = center.register(key: sc.keyCode, mods: sc.mods, handler: { [unowned self] in self.run(action, sc) }) {
                fixedIDs.append(id)
            } else {
                failed.append("\(action.title) (\(sc.display))")
            }
        }
    }

    private func run(_ action: ShortcutAction, _ sc: Shortcut) {
        func snap(_ a: SnapAction) { lastResult = WindowManager.perform(a) }
        switch action {
        case .snapLeft: snap(.left)
        case .snapRight: snap(.right)
        case .maximize: snap(.maximize)
        case .restore: snap(.restoreOrMinimize)
        case .moveDisplayLeft: snap(.moveDisplayLeft)
        case .moveDisplayRight: snap(.moveDisplayRight)
        case .enterFullScreen: snap(.enterFullScreen)
        case .exitFullScreen: snap(.exitFullScreen)
        case .switcherNext: advance(backwards: false, sc)
        case .switcherPrevious: advance(backwards: true, sc)
        case .clipboard: clipboard.toggle()
        case .menuBarToggle: menuBar.toggle()
        }
    }

    // MARK: Alt-Tab session

    private func advance(backwards: Bool, _ sc: Shortcut) {
        switcher.advance(backwards: backwards)
        if switcher.isActive, timer == nil { beginSession(sc) }
    }

    private func beginSession(_ sc: Shortcut) {
        hold = sc.holdFlags
        // While the modifier is held the arrows / Esc steer the switcher.
        func add(_ key: Int, _ h: @escaping () -> Void) {
            if let id = center.register(key: key, mods: sc.holdCarbon, handler: h) { sessionIDs.append(id) }
        }
        add(K.right) { [unowned self] in self.switcher.advance(backwards: false) }
        add(K.down)  { [unowned self] in self.switcher.advance(backwards: false) }
        add(K.left)  { [unowned self] in self.switcher.advance(backwards: true) }
        add(K.up)    { [unowned self] in self.switcher.advance(backwards: true) }
        add(K.esc)   { [unowned self] in self.endSession(commit: false) }

        // Releasing the modifier commits. Polled: reading the modifier state needs no permission.
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [unowned self] _ in
            let now = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !now.isSuperset(of: self.hold) { self.endSession(commit: true) }
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
