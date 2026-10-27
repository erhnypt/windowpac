import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum SnapAction {
    case left, right, maximize, restoreOrMinimize
    case moveDisplayLeft, moveDisplayRight
    case enterFullScreen, exitFullScreen
}

/// Moves / resizes the focused window through the Accessibility API.
/// All rects here are in AX coordinates: origin top-left of the primary display.
enum WindowManager {
    private static var savedFrames: [CGWindowID: CGRect] = [:]

    // MARK: AX helpers

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    static func isFullScreen(_ w: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &ref) == .success else { return false }
        return (ref as? Bool) ?? false
    }

    static func windowID(_ w: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(w, &id) == .success ? id : nil
    }

    static func frame(of w: AXUIElement) -> CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &ref) == .success,
              let pv = ref, AXValueGetValue(pv as! AXValue, .cgPoint, &p),
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &ref) == .success,
              let sv = ref, AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var origin = r.origin, size = r.size
        // size → position → size: resizing near a display edge or across
        // displays is clamped by the system unless repeated.
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
    }

    // MARK: Screens

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func axRect(_ ns: CGRect) -> CGRect {
        CGRect(x: ns.minX, y: primaryHeight - ns.maxY, width: ns.width, height: ns.height)
    }

    /// Screens left → right (then top → bottom).
    private static var orderedScreens: [NSScreen] {
        NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
    }

    private static func usable(_ s: NSScreen) -> CGRect { axRect(s.visibleFrame) }

    private static func screenIndex(for frame: CGRect, in screens: [NSScreen]) -> Int {
        var best = 0, bestArea: CGFloat = -1
        for (i, s) in screens.enumerated() {
            let i2 = axRect(s.frame).intersection(frame)
            let area = i2.isNull ? 0 : i2.width * i2.height
            if area > bestArea { best = i; bestArea = area }
        }
        return best
    }

    private static func halfRects(_ area: CGRect) -> (left: CGRect, right: CGRect) {
        let w = (area.width / 2).rounded(.down)
        return (CGRect(x: area.minX, y: area.minY, width: w, height: area.height),
                CGRect(x: area.minX + w, y: area.minY, width: area.width - w, height: area.height))
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12 &&
        abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }

    // MARK: Actions

    @discardableResult
    static func perform(_ action: SnapAction, retried: Bool = false) -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "no frontmost app" }
        guard let w = focusedWindow() else { NSSound.beep(); return "no focused window in \(app.localizedName ?? "?") (AX)" }

        // Native full-screen windows ignore resizing: leave full screen first, then redo the action.
        if isFullScreen(w) {
            switch action {
            case .enterFullScreen: return "already full screen"
            case .exitFullScreen, .restoreOrMinimize:
                AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, false as CFBoolean)
                return "left full screen"
            default:
                guard !retried else { return "could not leave full screen" }
                AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, false as CFBoolean)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { _ = perform(action, retried: true) }
                return "left full screen, applying \(action)…"
            }
        }
        guard let cur = frame(of: w) else { NSSound.beep(); return "cannot read window frame" }
        let id = windowID(w)
        let screens = orderedScreens
        guard !screens.isEmpty else { return "no screens" }
        let idx = screenIndex(for: cur, in: screens)
        let area = usable(screens[idx])
        let halves = halfRects(area)

        func remember() {
            guard let id, savedFrames[id] == nil else { return }
            savedFrames[id] = cur
        }

        switch action {
        case .left, .right:
            let isLeft = action == .left
            let target = isLeft ? halves.left : halves.right
            if near(cur, target), screens.count > 1 {
                // Already snapped on that side: continue onto the neighbouring
                // display, on its opposite half (Windows behaviour).
                let next = (idx + (isLeft ? -1 : 1) + screens.count) % screens.count
                let h = halfRects(usable(screens[next]))
                setFrame(w, isLeft ? h.right : h.left)
            } else {
                remember()
                setFrame(w, target)
            }

        case .maximize:
            remember()
            setFrame(w, area)

        case .restoreOrMinimize:
            if let id, let old = savedFrames.removeValue(forKey: id) {
                setFrame(w, old)
            } else {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, true as CFBoolean)
            }

        case .moveDisplayLeft, .moveDisplayRight:
            guard screens.count > 1 else { NSSound.beep(); return "only one display" }
            let step = action == .moveDisplayLeft ? -1 : 1
            let next = (idx + step + screens.count) % screens.count
            let src = area, dst = usable(screens[next])
            // Keep relative position and size on the new display.
            let rx = (cur.minX - src.minX) / src.width, ry = (cur.minY - src.minY) / src.height
            let rw = cur.width / src.width, rh = cur.height / src.height
            setFrame(w, CGRect(x: dst.minX + rx * dst.width, y: dst.minY + ry * dst.height,
                               width: rw * dst.width, height: rh * dst.height))

        case .enterFullScreen:
            AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, true as CFBoolean)
        case .exitFullScreen:
            AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, false as CFBoolean)
        }
        return "ok → \(app.localizedName ?? "?"), \(Int(cur.width))x\(Int(cur.height)) → \(frame(of: w).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "?")"
    }
}
