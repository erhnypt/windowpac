import Cocoa
import ScreenCaptureKit

/// Menu bar icon hider.
///
/// Items are created right-to-left (a later item appears left of an earlier one):
///   … other icons | [separator] [dividers] [‹ ›] [WindowPac icon]
/// The user ⌘-drags icons to the left of the separator. Collapsing puts a cover window over everything left
/// of it. The cover shows a capture of the real menu bar background (wallpaper + tint, with all status icons
/// excluded) so it looks as if the icons were gone. Pushing icons away with a huge status item (Hidden Bar's
/// trick) does not work on current macOS versions, hence the cover.
final class MenuBarManager: NSObject {
    private var toggleItem: NSStatusItem?
    private var separator: NSStatusItem?
    private var dividers: [NSStatusItem] = []
    private var signature = ""
    private var autoHideTimer: Timer?
    private var refreshTimer: Timer?
    private var ticks = 0
    private(set) var collapsed = false

    private var cover: CoverPanel?
    private var coverView: CoverView?
    private var coverRect = CGRect.zero        // CG coordinates (origin top-left of the primary display)
    private var captureToken = 0

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

    // MARK: Items

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

        // Last created = leftmost: everything left of this one is the hidden zone.
        let s = bar.statusItem(withLength: 12)
        s.autosaveName = "wp_separator"
        s.button?.title = "|"
        s.button?.alphaValue = 0.45
        separator = s
        render()
    }

    private func remove() {
        autoHideTimer?.invalidate(); autoHideTimer = nil
        stopCover()
        let bar = NSStatusBar.system
        ([toggleItem, separator] + dividers.map { Optional($0) }).compactMap { $0 }.forEach { bar.removeStatusItem($0) }
        toggleItem = nil; separator = nil; dividers = []
    }

    private func render() {
        toggleItem?.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
                                            accessibilityDescription: "Show or hide menu bar icons")
        toggleItem?.button?.toolTip = collapsed ? "Show hidden menu bar icons" : "Hide menu bar icons left of |"
        if collapsed { startCover() } else { stopCover() }
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate(); autoHideTimer = nil
        let secs = Settings.menuBarAutoHide
        guard !collapsed, secs > 0, toggleItem != nil else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: false) { [weak self] _ in
            self?.setCollapsed(true)
        }
    }

    @objc private func clicked() { toggle() }

    // MARK: Cover

    private func startCover() {
        refreshTimer?.invalidate()
        ticks = 0
        refreshCover(force: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            // Icons come and go; the wallpaper / appearance may change: re-capture now and then.
            self.refreshCover(force: self.ticks % 30 == 0)
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func stopCover() {
        refreshTimer?.invalidate(); refreshTimer = nil
        captureToken += 1
        cover?.orderOut(nil)
        coverRect = .zero
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Finds the icons left of the separator and (re)positions the cover over them.
    private func refreshCover(force: Bool) {
        guard collapsed, let sepWin = separator?.button?.window else { cover?.orderOut(nil); return }
        let sf = sepWin.frame
        let sep = CGRect(x: sf.minX, y: primaryHeight - sf.maxY, width: sf.width, height: sf.height)

        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        var minX = CGFloat.greatestFiniteMagnitude
        for d in info where (d[kCGWindowLayer as String] as? Int) == 25 {
            guard (d[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"],
                  abs(y - sep.minY) < 8, x + w <= sep.minX + 2 else { continue }
            minX = min(minX, x)
        }
        guard minX < sep.minX else { cover?.orderOut(nil); coverRect = .zero; return }

        let rect = CGRect(x: minX - 2, y: sep.minY, width: sep.minX - minX + 2, height: sep.height)
        let moved = abs(rect.minX - coverRect.minX) > 1 || abs(rect.width - coverRect.width) > 1
            || abs(rect.minY - coverRect.minY) > 1
        guard moved || force || cover?.isVisible != true else { return }
        coverRect = rect

        let panel = cover ?? makeCover()
        panel.setFrame(CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height),
                       display: false)
        if moved || force { captureBackground() }
        panel.orderFrontRegardless()
    }

    private func makeCover() -> CoverPanel {
        let p = CoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        p.isOpaque = true
        p.backgroundColor = NSColor(white: 0.12, alpha: 1)     // fallback until / unless a capture is available
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = CoverView()
        v.onClick = { [weak self] in self?.setCollapsed(false) }
        p.contentView = v
        cover = p; coverView = v
        return p
    }

    /// Captures the menu bar as it looks without any status icon (needs Screen Recording permission).
    private func captureBackground() {
        guard CGPreflightScreenCaptureAccess() else { _ = CGRequestScreenCaptureAccess(); return }
        captureToken += 1
        let token = captureToken
        let rect = coverRect
        Task { @MainActor [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { CGDisplayBounds($0.displayID).intersects(rect) })
            else { return }
            let bounds = CGDisplayBounds(display.displayID)
            // Everything at or above the status layer (all menu bar icons, and this cover) stays out of the picture.
            let excluded = content.windows.filter { $0.windowLayer >= 25 }
            let cfg = SCStreamConfiguration()
            let scale = NSScreen.screens.first(where: { $0.frame.intersects(CGRect(x: rect.minX, y: self?.primaryHeight ?? 0 - rect.maxY,
                                                                                    width: rect.width, height: rect.height)) })?.backingScaleFactor ?? 2
            cfg.sourceRect = CGRect(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY, width: rect.width, height: rect.height)
            cfg.width = max(1, Int(rect.width * scale)); cfg.height = max(1, Int(rect.height * scale))
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: excluded), configuration: cfg),
                  let self, token == self.captureToken, self.collapsed else { return }
            self.coverView?.image = NSImage(cgImage: img, size: rect.size)
        }
    }

    /// Troubleshooting: where every menu bar item currently is (x position, left → right).
    func layoutReport() -> String {
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        var rows: [(CGFloat, String)] = []
        for d in info where (d[kCGWindowLayer as String] as? Int) == 25 {
            guard let b = d[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let w = b["Width"] else { continue }
            let owner = d[kCGWindowOwnerName as String] as? String ?? "?"
            let mine = (d[kCGWindowOwnerPID as String] as? pid_t) == me ? "  ← WindowPac" : ""
            let on = (d[kCGWindowIsOnscreen as String] as? Bool) == true ? "" : "  [offscreen]"
            rows.append((x, "x=\(Int(x))  w=\(Int(w))  \(owner)\(on)\(mine)"))
        }
        let screen = NSScreen.main.map { "screen width \(Int($0.frame.width))" } ?? ""
        return "collapsed=\(collapsed)  cover=\(Int(coverRect.minX)),\(Int(coverRect.width))  \(screen)  "
            + "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
            + rows.sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: "\n")
    }
}

private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Borderless windows may sit over the menu bar; don't let AppKit push them below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class CoverView: NSImageView {
    var onClick: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleAxesIndependently
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
