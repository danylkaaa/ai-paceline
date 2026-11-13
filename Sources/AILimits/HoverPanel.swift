import AppKit
import SwiftUI

/// Borderless floating panel under the menu bar item; it takes clicks without activating the app.
@MainActor
final class HoverPanel: NSPanel {
    private var host: NSHostingView<PanelView>!
    private let ui = PanelState()

    init(store: UsageStore) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        host = NSHostingView(rootView: PanelView(store: store, onResize: { [weak self] in self?.refit() }, ui: ui))
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    /// Fits the panel to its content and keeps its top edge in place.
    func refit() {
        guard isVisible else { return }
        let size = host.fittingSize
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Fits the panel to its content and places it under `anchor`, inside the screen.
    func resize(anchor: NSRect) {
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let x = min(max(visible.minX + 8, anchor.midX - size.width / 2), visible.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }
}
