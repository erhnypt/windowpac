import Cocoa
import SwiftUI
import ScreenCaptureKit

/// One status item window of another app (layer 25 in the window server).
struct StatusWindow {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let bounds: CGRect        // CG coordinates (origin top-left of the primary display)
}

enum StatusBar {
    /// Apple's own items (Wi-Fi, clock, …) are not offered for hiding.
    private static let systemOwners: Set<String> = [
        "Control Center", "ControlCenter", "SystemUIServer", "Window Server", "Spotlight", "Dock",
        "TextInputMenuAgent", "Notification Center", "WindowManager", "Siri"]

    /// Third-party status items currently on screen, left → right.
    static func windows() -> [StatusWindow] {
        let me = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var out: [StatusWindow] = []
        for d in info where (d[kCGWindowLayer as String] as? Int) == 25 {
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let owner = d[kCGWindowOwnerName as String] as? String, !systemOwners.contains(owner),
                  let id = d[kCGWindowNumber as String] as? UInt32,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  h <= 60, y <= 40, w >= 8 else { continue }
            out.append(StatusWindow(id: id, pid: pid, owner: owner, bounds: CGRect(x: x, y: y, width: w, height: h)))
        }
        return out.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func bundleID(of pid: pid_t) -> String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    /// Opens the menu of the app's status item nearest to `midX` by "pressing" it through Accessibility.
    static func press(pid: pid_t, midX: CGFloat) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &ref) == .success,
              let bar = ref, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return false }
        var best: (AXUIElement, CGFloat)?
        for it in items {
            guard let f = WindowManager.frame(of: it) else { continue }
            let d = abs(f.midX - midX)
            if best == nil || d < best!.1 { best = (it, d) }
        }
        guard let (el, d) = best, d < 24 else { return false }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }
}

struct HiddenTile: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let name: String
    let icon: NSImage?
}

final class DropModel: ObservableObject {
    @Published var tiles: [HiddenTile] = []
}

private struct DropView: View {
    @ObservedObject var model: DropModel
    var onPick: (HiddenTile) -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hidden menu bar items").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if model.tiles.isEmpty {
                Text("Nothing hidden yet. Choose which apps to hide in Settings → Menu bar.")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 250, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: min(4, max(1, model.tiles.count))),
                          spacing: 8) {
                    ForEach(model.tiles) { t in
                        Button { onPick(t) } label: {
                            VStack(spacing: 5) {
                                if let ic = t.icon { Image(nsImage: ic).resizable().frame(width: 30, height: 30) }
                                Text(t.name).font(.system(size: 10)).lineLimit(1)
                            }
                            .frame(width: 78, height: 70)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("Choose apps…", action: onSettings).buttonStyle(.link).font(.caption)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Hides the menu bar icons of chosen apps and lists them in a Control Center–style card under WindowPac's button.
///
/// Hiding: each chosen app's status icon is covered by a small window showing a capture of the real menu bar
/// background (all icons excluded), so it looks as if the icon were gone (the gap stays). Pushing icons away with a
/// huge status item no longer works on current macOS.
/// Using: the card's tiles press the real item through Accessibility, which opens that app's menu.
final class MenuBarManager: NSObject {
    private var item: NSStatusItem?
    private var covers: [CGWindowID: CoverPanel] = [:]
    private var refreshTimer: Timer?
    private var layout = ""
    private var ticks = 0
    private var captureToken = 0
    private var drop: DropPanel?
    private var resignObserver: NSObjectProtocol?
    private let model = DropModel()
    var openSettings: (() -> Void)?

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    func apply() {
        guard Settings.menuBarEnabled else { remove(); return }
        if item == nil { install() }
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.ticks += 1
                // Icons come and go and the wallpaper may change: re-capture now and then.
                self.refresh(force: self.ticks % 30 == 0)
            }
            RunLoop.main.add(refreshTimer!, forMode: .common)
        }
        refresh(force: true)
    }

    func toggle() { drop?.isVisible == true ? hidePanel() : showPanel() }

    private func install() {
        let t = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        t.autosaveName = "wp_hidden_items"
        t.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Hidden menu bar items")
        t.button?.toolTip = "Hidden menu bar items"
        t.button?.target = self
        t.button?.action = #selector(clicked)
        item = t
    }

    private func remove() {
        refreshTimer?.invalidate(); refreshTimer = nil
        captureToken += 1
        hidePanel()
        covers.values.forEach { $0.orderOut(nil) }
        covers = [:]
        layout = ""
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func clicked() { toggle() }

    // MARK: Covers

    private func hiddenWindows() -> [StatusWindow] {
        let ids = Set(Settings.menuBarHiddenApps)
        guard !ids.isEmpty else { return [] }
        return StatusBar.windows().filter { ids.contains(StatusBar.bundleID(of: $0.pid) ?? "") }
    }

    private func refresh(force: Bool) {
        let wins = hiddenWindows()
        let key = wins.map { "\($0.id):\(Int($0.bounds.minX)):\(Int($0.bounds.width))" }.joined(separator: ",")
        let changed = key != layout
        layout = key

        for (id, p) in covers where !wins.contains(where: { $0.id == id }) { p.orderOut(nil); covers[id] = nil }
        for w in wins {
            let p = covers[w.id] ?? makeCover()
            covers[w.id] = p
            let r = w.bounds.insetBy(dx: -1, dy: 0)
            p.setFrame(CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height), display: false)
            p.orderFrontRegardless()
        }
        if (changed || force) && !wins.isEmpty { captureBackgrounds(wins) }
    }

    private func makeCover() -> CoverPanel {
        let p = CoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        p.isOpaque = true
        p.backgroundColor = NSColor(white: 0.12, alpha: 1)     // fallback until / unless a capture is available
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = CoverView()
        v.onClick = { [weak self] in self?.toggle() }
        p.contentView = v
        return p
    }

    /// The menu bar as it looks without any status icon (needs Screen Recording permission).
    private func captureBackgrounds(_ wins: [StatusWindow]) {
        guard CGPreflightScreenCaptureAccess() else { _ = CGRequestScreenCaptureAccess(); return }
        captureToken += 1
        let token = captureToken
        let targets = wins.map { ($0.id, $0.bounds.insetBy(dx: -1, dy: 0)) }
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        Task { @MainActor [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
            // Everything at or above the status layer (all icons, and our covers) stays out of the picture.
            let excluded = content.windows.filter { $0.windowLayer >= 25 }
            for (id, rect) in targets {
                guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).intersects(rect) }) else { continue }
                let bounds = CGDisplayBounds(display.displayID)
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY, width: rect.width, height: rect.height)
                cfg.width = max(1, Int(rect.width * scale)); cfg.height = max(1, Int(rect.height * scale))
                cfg.showsCursor = false
                guard let img = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: excluded), configuration: cfg),
                      let self, token == self.captureToken else { continue }
                (self.covers[id]?.contentView as? CoverView)?.image = NSImage(cgImage: img, size: rect.size)
            }
        }
    }

    // MARK: Drop-down card

    private func showPanel() {
        guard let button = item?.button, let bw = button.window else { return }
        model.tiles = hiddenWindows().map { w in
            let app = NSRunningApplication(processIdentifier: w.pid)
            return HiddenTile(id: w.id, pid: w.pid, name: app?.localizedName ?? w.owner, icon: app?.icon)
        }
        let view = DropView(model: model, onPick: { [weak self] in self?.activate($0) },
                            onSettings: { [weak self] in self?.hidePanel(); self?.openSettings?() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = drop ?? DropPanel(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host

        let bf = bw.frame
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: bf.midX, y: bf.midY)) } ?? NSScreen.main
        let sf = screen?.frame ?? bf
        let x = min(max(bf.maxX - size.width, sf.minX + 8), sf.maxX - size.width - 8)
        p.setFrame(CGRect(x: x, y: bf.minY - size.height - 6, width: size.width, height: size.height), display: true)
        drop = p
        p.makeKeyAndOrderFront(nil)
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in self?.hidePanel() }
        }
    }

    private func hidePanel() { drop?.orderOut(nil) }

    private func activate(_ tile: HiddenTile) {
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let b = StatusBar.windows().first { $0.id == tile.id }?.bounds
            if let b, StatusBar.press(pid: tile.pid, midX: b.midX) { return }
            if let b { self.clickFallback(at: b) }
        }
    }

    /// For apps that don't expose their status item to Accessibility: briefly lift the covers and click the real icon.
    private func clickFallback(at b: CGRect) {
        covers.values.forEach { $0.orderOut(nil) }
        let pt = CGPoint(x: b.midX, y: b.midY)
        let saved = CGEvent(source: nil)?.location ?? pt
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            CGWarpMouseCursorPosition(saved)
            self?.refresh(force: true)
        }
    }
}

private final class DropPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
