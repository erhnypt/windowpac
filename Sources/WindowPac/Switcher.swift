import Cocoa
import ApplicationServices
import ScreenCaptureKit

struct WinItem {
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let ax: AXUIElement?       // nil: window lives on another Space and AX can't see it
    let minimized: Bool
    var noWindow = false       // running app without any window
    var windowID: CGWindowID?  // for thumbnails
}

/// Windows-style Alt-Tab: one entry per *window* (not per app), across all
/// displays and Spaces, including minimized windows.
final class Switcher {
    private(set) var isActive = false
    private var items: [WinItem] = []
    private var selected = 0
    private var panel: NSPanel?
    private var view: SwitcherView?
    private var session = 0

    // MARK: Enumeration

    static func enumerate() -> [WinItem] {
        // Front-to-back order of every window the window server knows, on all Spaces.
        let info = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        var order: [CGWindowID: Int] = [:]
        for (i, d) in info.enumerated() {
            if let n = d[kCGWindowNumber as String] as? UInt32 { order[n] = i }
        }

        var ranked: [(Int, WinItem)] = []
        var seen = Set<CGWindowID>()
        var pidsWithItems = Set<pid_t>()

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let wins = ref as? [AXUIElement] else { continue }
            for w in wins {
                let sub = str(w, kAXSubroleAttribute)
                guard sub == "AXStandardWindow" || sub == "AXDialog" else { continue }
                var id: CGWindowID = 0
                let hasID = _AXUIElementGetWindow(w, &id) == .success
                if hasID { seen.insert(id) }
                pidsWithItems.insert(app.processIdentifier)
                let title = str(w, kAXTitleAttribute) ?? ""
                let mini = (try? bool(w, kAXMinimizedAttribute)) ?? false
                let item = WinItem(pid: app.processIdentifier, appName: app.localizedName ?? "?",
                                   title: title, icon: app.icon, ax: w, minimized: mini,
                                   windowID: hasID ? id : nil)
                ranked.append((hasID ? (order[id] ?? Int.max - 1) : Int.max - 1, item))
            }
        }

        // Windows on other Spaces: AX doesn't list them, CGWindowList does.
        for d in info {
            guard let n = d[kCGWindowNumber as String] as? UInt32, !seen.contains(n),
                  (d[kCGWindowLayer as String] as? Int) == 0,
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  (d[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 200, (b["Height"] ?? 0) >= 100 else { continue }
            let title = d[kCGWindowName as String] as? String ?? ""
            pidsWithItems.insert(pid)
            ranked.append((order[n] ?? Int.max,
                           WinItem(pid: pid, appName: app.localizedName ?? "?", title: title,
                                   icon: app.icon, ax: nil, minimized: false, windowID: n)))
        }

        if Settings.showWindowlessApps {
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && !pidsWithItems.contains(app.processIdentifier) {
                var item = WinItem(pid: app.processIdentifier, appName: app.localizedName ?? "?", title: "",
                                   icon: app.icon, ax: nil, minimized: false)
                item.noWindow = true
                ranked.append((Int.max, item))
            }
        }

        return ranked.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func str(_ e: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func bool(_ e: AXUIElement, _ attr: String) throws -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return false }
        return (ref as? Bool) ?? false
    }

    // MARK: Session

    func advance(backwards: Bool) {
        if !isActive {
            items = Switcher.enumerate()
            guard items.count > 1 else { return }
            isActive = true
            session += 1
            selected = backwards ? items.count - 1 : 1
            show()
            loadThumbnails()
        } else {
            selected = (selected + (backwards ? -1 : 1) + items.count) % items.count
            view?.selected = selected
        }
    }

    func cancel() { finish(activate: false) }
    func commit() { finish(activate: true) }

    private func finish(activate: Bool) {
        guard isActive else { return }
        isActive = false
        session += 1
        panel?.orderOut(nil)
        panel = nil; view = nil
        if activate, items.indices.contains(selected) { Switcher.activate(items[selected]) }
        items = []
    }

    static func activate(_ item: WinItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if item.noWindow {
            // Asking the app to "reopen" makes most apps create a new window (like clicking its Dock icon).
            app.unhide()
            if let url = app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else { app.activate(options: [.activateIgnoringOtherApps]) }
            return
        }
        if let ax = item.ax {
            if item.minimized { AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, false as CFBoolean) }
            app.activate(options: [.activateIgnoringOtherApps])
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, true as CFBoolean)
        } else {
            // Other Space: activating the app makes macOS switch to its Space.
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: Thumbnails (needs Screen Recording permission; icons are shown without it)

    private func loadThumbnails() {
        guard CGPreflightScreenCaptureAccess() else { _ = CGRequestScreenCaptureAccess(); return }
        let mine = session
        let wanted = items.enumerated().compactMap { i, it in it.windowID.map { (i, $0) } }
        Task { @MainActor [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            for (i, wid) in wanted {
                guard let self, self.isActive, self.session == mine else { return }
                guard let w = byID[wid], w.frame.width > 1, w.frame.height > 1 else { continue }
                let cfg = SCStreamConfiguration()
                let scale = min(1, 400 / w.frame.width)
                cfg.width = max(1, Int(w.frame.width * scale)); cfg.height = max(1, Int(w.frame.height * scale))
                cfg.showsCursor = false
                if let img = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg),
                   self.isActive, self.session == mine {
                    self.view?.setThumbnail(img, at: i)
                }
            }
        }
    }

    // MARK: Overlay

    private func show() {
        let v = SwitcherView(items: items)
        v.selected = selected
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: v.frame.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Frosted background is the container; the item view draws on top of it.
        let fx = NSVisualEffectView(frame: CGRect(origin: .zero, size: v.frame.size))
        fx.material = .hudWindow; fx.state = .active; fx.blendingMode = .behindWindow
        fx.wantsLayer = true; fx.layer?.cornerRadius = 16; fx.layer?.masksToBounds = true
        fx.addSubview(v)
        p.contentView = fx
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(CGPoint(x: f.midX - v.frame.width / 2, y: f.midY - v.frame.height / 2))
        }
        p.orderFrontRegardless()
        panel = p; view = v
    }
}

private final class SwitcherView: NSView {
    private let items: [WinItem]
    private let cols: Int
    private let cellW: CGFloat = 200, cellH: CGFloat = 150, pad: CGFloat = 16
    private var thumbs: [Int: NSImage] = [:]
    var selected = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(items: [WinItem]) {
        self.items = items
        cols = min(items.count, 6)
        let rows = (items.count + cols - 1) / cols
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(cols) * cellW + pad * 2,
                                 height: CGFloat(rows) * cellH + pad * 2))
    }
    required init?(coder: NSCoder) { fatalError() }

    func setThumbnail(_ img: CGImage, at i: Int) {
        thumbs[i] = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        needsDisplay = true
    }

    private func fit(_ size: CGSize, in box: CGRect) -> CGRect {
        let k = min(box.width / size.width, box.height / size.height, 1.5)
        let w = size.width * k, h = size.height * k
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        for (i, it) in items.enumerated() {
            let r = CGRect(x: pad + CGFloat(i % cols) * cellW, y: pad + CGFloat(i / cols) * cellH,
                           width: cellW, height: cellH).insetBy(dx: 4, dy: 4)
            if i == selected {
                NSColor.white.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            }
            let box = CGRect(x: r.minX + 8, y: r.minY + 8, width: r.width - 16, height: 92)
            let dim: CGFloat = (it.minimized || it.noWindow) ? 0.5 : 1
            if let t = thumbs[i] {
                let tr = fit(t.size, in: box)
                t.draw(in: tr, from: .zero, operation: .sourceOver, fraction: dim, respectFlipped: true, hints: nil)
                NSColor.white.withAlphaComponent(0.3).setStroke()
                NSBezierPath(rect: tr).stroke()
            } else {
                it.icon?.draw(in: CGRect(x: box.midX - 32, y: box.midY - 32, width: 64, height: 64),
                              from: .zero, operation: .sourceOver, fraction: dim, respectFlipped: true, hints: nil)
            }
            let row = CGRect(x: r.minX + 8, y: r.minY + 106, width: r.width - 16, height: 18)
            it.icon?.draw(in: CGRect(x: row.minX, y: row.minY, width: 16, height: 16),
                          from: .zero, operation: .sourceOver, fraction: dim, respectFlipped: true, hints: nil)
            let name = it.title.isEmpty ? it.appName : it.title
            NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: para])
                .draw(in: CGRect(x: row.minX + 22, y: row.minY, width: row.width - 22, height: 16))
            let sub = it.noWindow ? "no window" : (it.minimized ? "minimized" : (it.title.isEmpty ? "" : it.appName))
            NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para])
                .draw(in: CGRect(x: row.minX + 22, y: row.minY + 16, width: row.width - 22, height: 14))
        }
    }
}
