import AppKit
import Combine
import SwiftUI

/// Menu bar item: opens the panel on hover (pinned on click), closes it when the pointer leaves.
@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let label: NSHostingView<MenuBarLabel>
    private let tracker = HoverTrackingView()
    private let panel: HoverPanel
    private var pinned = false
    private var openWork: DispatchWorkItem?
    private var closeTimer: Timer?
    private var lastInside = Date()
    private var clickMonitor: Any?
    private var subscriptions: [AnyCancellable] = []

    init(store: UsageStore) {
        label = PassThroughHostingView(rootView: MenuBarLabel(store: store))
        panel = HoverPanel(store: store)
        super.init()

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        for view in [label, tracker] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
        tracker.onEnter = { [weak self] in self?.pointerEntered() }
        tracker.onExit = { [weak self] in self?.openWork?.cancel() }

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.relayout() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &subscriptions)
        relayout()
    }

    private func relayout() {
        item.length = max(24, label.fittingSize.width)
        if panel.isVisible { DispatchQueue.main.async { self.panel.refit() } }
    }

    private var statusFrame: NSRect { item.button?.window?.frame ?? .zero }

    private func pointerEntered() {
        guard !panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.statusFrame.contains(NSEvent.mouseLocation) else { return }
            self.show(pinned: false)
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @objc private func clicked() {
        if panel.isVisible && pinned { close(); return }
        show(pinned: true)
    }

    private func show(pinned: Bool) {
        self.pinned = pinned
        lastInside = Date()
        panel.resize(anchor: statusFrame)
        panel.orderFrontRegardless()
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfPointerLeft() }
        }
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
    }

    private func closeIfPointerLeft() {
        guard !pinned else { return }
        let p = NSEvent.mouseLocation
        if panel.frame.insetBy(dx: -6, dy: -6).contains(p) || statusFrame.contains(p) {
            lastInside = Date()
        } else if Date().timeIntervalSince(lastInside) > 0.5 {
            close()
        }
    }

    private func close() {
        pinned = false
        closeTimer?.invalidate()
        closeTimer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
    }
}

/// Lets clicks fall through to the status bar button.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
