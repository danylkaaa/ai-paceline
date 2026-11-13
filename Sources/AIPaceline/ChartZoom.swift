import AppKit
import SwiftUI

/// Time window of a chart: a zoom level in days and how far it is moved back from today.
@MainActor
final class ChartZoom: ObservableObject {
    let levels: [Double]
    @Published private(set) var index: Int
    @Published private(set) var offsetDays: Double = 0
    private var wheel = 0.0, pan = 0.0, pinch = 0.0

    init(levels: [Double], initial: Double) {
        self.levels = levels
        index = levels.firstIndex(of: initial) ?? levels.count - 1
    }

    var days: Double { levels[index] }
    var maxDays: Double { levels[levels.count - 1] }

    /// Visible range ending `offsetDays` before `end`.
    func range(endingAt end: Date) -> ClosedRange<Date> {
        let last = end.addingTimeInterval(-offsetDays * 86400)
        return last.addingTimeInterval(-days * 86400)...last
    }

    func scrolled(dx: CGFloat, dy: CGFloat, precise: Bool) {
        let unit = precise ? 30.0 : 1.0
        wheel += dy
        if abs(wheel) >= unit {
            step(wheel > 0 ? -1 : 1)
            wheel = 0
        }
        pan += dx
        if abs(pan) >= unit {
            move(by: (pan > 0 ? 1 : -1) * max(1, days / 7))
            pan = 0
        }
    }

    func pinched(_ magnification: CGFloat) {
        pinch += magnification
        if abs(pinch) >= 0.12 {
            step(pinch > 0 ? -1 : 1)
            pinch = 0
        }
    }

    private func step(_ delta: Int) {
        index = min(max(0, index + delta), levels.count - 1)
        move(by: 0)
    }

    private func move(by delta: Double) {
        offsetDays = min(max(0, offsetDays + delta), maxDays - days)
    }

    var label: String {
        let span = days < 1 ? "\(Int(days * 24)) h" : days == 1 ? "1 day" : "\(Int(days)) days"
        return offsetDays > 0 ? "\(span), ending \(Int(offsetDays))d ago" : "last \(span)"
    }
}

extension View {
    /// Scroll wheel and pinch over this view change the zoom instead of scrolling the panel.
    @ViewBuilder func zoomable(_ zoom: ChartZoom) -> some View {
        // Snapshots and --open screenshots keep the default window, whatever the pointer does.
        if Snapshot.active || Launch.open != nil { self } else { overlay(ZoomCatcher(zoom: zoom)) }
    }
}

private struct ZoomCatcher: NSViewRepresentable {
    let zoom: ChartZoom

    func makeNSView(context: Context) -> ZoomCatcherView {
        let view = ZoomCatcherView()
        view.zoom = zoom
        return view
    }

    func updateNSView(_ view: ZoomCatcherView, context: Context) { view.zoom = zoom }
}

final class ZoomCatcherView: NSView {
    weak var zoom: ChartZoom?

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        MainActor.assumeIsolated { zoom?.scrolled(dx: dx, dy: dy, precise: precise) }
    }

    override func magnify(with event: NSEvent) {
        let m = event.magnification
        MainActor.assumeIsolated { zoom?.pinched(m) }
    }
}

struct ZoomHint: View {
    @ObservedObject var zoom: ChartZoom

    var body: some View {
        Text("\(zoom.label) · pinch or scroll to zoom, swipe sideways to move")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
