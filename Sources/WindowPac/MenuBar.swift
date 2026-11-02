import Cocoa

/// Hides menu bar icons the way Hidden Bar does: an invisible separator item grows very wide, which pushes
/// every icon that sits to its left off screen. The user arranges icons by ⌘-dragging them across the
/// separator; ‹ › collapses / expands. Extra "|" dividers only mark blocks in the always-visible area.
///
/// Items are created right-to-left (a later item appears left of an earlier one):
///   … other icons | [separator] [dividers] [‹ ›] [WindowPac icon]
final class MenuBarManager: NSObject {
    private var toggleItem: NSStatusItem?
    private var separator: NSStatusItem?
    private var dividers: [NSStatusItem] = []
    private var signature = ""
    private var timer: Timer?
    private(set) var collapsed = false

    var isInstalled: Bool { toggleItem != nil }

    func apply() {
        guard Settings.menuBarEnabled else { remove(); signature = ""; return }
        let sig = "\(Settings.menuBarDividers)"
        if sig != signature || toggleItem == nil { install(); signature = sig }
        scheduleAutoHide()
    }

    func toggle() { setCollapsed(!collapsed) }

    private func setCollapsed(_ c: Bool) {
        guard toggleItem != nil else { return }
        collapsed = c
        Settings.menuBarCollapsed = c
        render()
        scheduleAutoHide()
    }

    private func install() {
        remove()
        collapsed = Settings.menuBarCollapsed
        let bar = NSStatusBar.system

        let t = bar.statusItem(withLength: NSStatusItem.squareLength)
        t.autosaveName = "wp_toggle"
        t.button?.target = self
        t.button?.action = #selector(clicked)
        toggleItem = t

        for i in 0..<Settings.menuBarDividers {
            let d = bar.statusItem(withLength: 10)
            d.autosaveName = "wp_divider\(i)"
            d.button?.title = "|"
            d.button?.alphaValue = 0.45
            dividers.append(d)
        }

        // Last created = leftmost: everything left of this one can be hidden.
        let s = bar.statusItem(withLength: NSStatusItem.variableLength)
        s.autosaveName = "wp_separator"
        separator = s
        render()
    }

    private func remove() {
        timer?.invalidate(); timer = nil
        let bar = NSStatusBar.system
        ([toggleItem, separator] + dividers.map { Optional($0) }).compactMap { $0 }.forEach { bar.removeStatusItem($0) }
        toggleItem = nil; separator = nil; dividers = []
    }

    private func render() {
        toggleItem?.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
                                            accessibilityDescription: "Show or hide menu bar icons")
        toggleItem?.button?.toolTip = collapsed ? "Show hidden menu bar icons" : "Hide menu bar icons left of |"
        separator?.length = collapsed ? 10_000 : NSStatusItem.variableLength
        separator?.button?.title = collapsed ? "" : "|"
        separator?.button?.alphaValue = 0.45
    }

    private func scheduleAutoHide() {
        timer?.invalidate(); timer = nil
        let secs = Settings.menuBarAutoHide
        guard !collapsed, secs > 0, toggleItem != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: false) { [weak self] _ in
            self?.setCollapsed(true)
        }
    }

    /// Troubleshooting: where every menu bar item currently is (x position, left → right).
    func layoutReport() -> String {
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let mine = Set([toggleItem, separator].compactMap { $0?.button?.window?.windowNumber }
                       + dividers.compactMap { $0.button?.window?.windowNumber })
        var rows: [(CGFloat, String)] = []
        for d in info where (d[kCGWindowLayer as String] as? Int) == 25 {
            guard let b = d[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let w = b["Width"] else { continue }
            let owner = d[kCGWindowOwnerName as String] as? String ?? "?"
            let n = d[kCGWindowNumber as String] as? Int ?? -1
            let tag = n == separator?.button?.window?.windowNumber ? "  ← SEPARATOR"
                : (mine.contains(n) ? "  ← WindowPac" : "")
            let on = (d[kCGWindowIsOnscreen as String] as? Bool) == true ? "" : "  [offscreen]"
            rows.append((x, "x=\(Int(x))  w=\(Int(w))  \(owner)\(on)\(tag)"))
        }
        let screen = NSScreen.main.map { "screen width \(Int($0.frame.width))" } ?? ""
        return "collapsed=\(collapsed)  \(screen)  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
            + rows.sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: "\n")
    }

    @objc private func clicked() { toggle() }
}
