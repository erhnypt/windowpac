import Cocoa
import SwiftUI
import Combine

private struct BatteryWidgetView: View {
    @ObservedObject var model: BatteryModel

    private func tint(_ r: BatteryRow) -> Color {
        r.charging ? .green : (r.percent <= 20 ? .red : (r.percent <= 40 ? .orange : .green))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.rows.isEmpty {
                Text("No battery information").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.rows) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.symbol).frame(width: 22).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(r.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            if r.charging { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.green) }
                            Text("\(r.percent)%").font(.system(size: 12).monospacedDigit())
                        }
                        ProgressView(value: Double(r.percent), total: 100).tint(tint(r))
                        if let d = r.detail { Text(d).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A small always-on-desktop panel (below normal windows, above the icons). Draggable; remembers its position.
final class BatteryWidget {
    private let model = BatteryModel()
    private var panel: NSPanel?
    private var host: NSHostingView<BatteryWidgetView>?
    private var bag = Set<AnyCancellable>()
    private let posKey = "batteryWidgetTopLeft"

    func apply() { Settings.batteryWidgetEnabled ? show() : hide() }
    func refresh() { model.refresh() }

    private func show() {
        if panel == nil { build() }
        panel?.orderFrontRegardless()
        model.start()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.stop()
    }

    private func build() {
        let h = NSHostingView(rootView: BatteryWidgetView(model: model))
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: h.fittingSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = h
        panel = p; host = h

        place(topLeft: savedTopLeft() ?? defaultTopLeft(size: h.fittingSize))

        // Grow / shrink downwards when the number of devices changes.
        model.$rows.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.resize() }
        }.store(in: &bag)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: p)
            .sink { [weak self] _ in
                guard let self, let f = self.panel?.frame else { return }
                UserDefaults.standard.set(NSStringFromPoint(CGPoint(x: f.minX, y: f.maxY)), forKey: self.posKey)
            }.store(in: &bag)
    }

    private func resize() {
        guard let p = panel, let h = host else { return }
        let size = h.fittingSize
        p.setFrame(CGRect(x: p.frame.minX, y: p.frame.maxY - size.height, width: size.width, height: size.height),
                   display: true)
    }

    private func place(topLeft: CGPoint) {
        guard let p = panel, let h = host else { return }
        let size = h.fittingSize
        p.setFrame(CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
    }

    private func savedTopLeft() -> CGPoint? {
        guard let s = UserDefaults.standard.string(forKey: posKey) else { return nil }
        let pt = NSPointFromString(s)
        // Ignore a position that is no longer on any screen (display unplugged).
        return NSScreen.screens.contains { $0.frame.contains(CGPoint(x: pt.x + 20, y: pt.y - 20)) } ? pt : nil
    }

    private func defaultTopLeft(size: CGSize) -> CGPoint {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: f.maxX - size.width - 24, y: f.maxY - 24)
    }
}
