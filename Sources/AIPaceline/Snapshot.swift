import AppKit
import SwiftUI

/// `AIPaceline --snapshot <dir>`: fetches real data, writes one PNG per tab, and exits. Used to check the UI.
@MainActor
enum Snapshot {
    /// ImageRenderer cannot draw AppKit views, so snapshot mode leaves them out.
    nonisolated(unsafe) static var active = false

    static func run(into dir: URL) {
        active = true
        let store = UsageStore()
        let ui = PanelState()
        ui.scrolls = false
        Task {
            await store.backfillCodexHistory()
            await store.refresh(waitForTokens: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for scheme in [ColorScheme.dark, .light] {
                for (name, tab, settings) in Tab.allCases.map({ ($0.rawValue.lowercased(), $0, false) }) + [("settings", Tab.overview, true)] {
                    AppDefaults.store.set(tab.rawValue, forKey: "tab")
                    ui.showSettings = settings
                    let view = PanelView(store: store, ui: ui)
                        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("\(name)-\(scheme).png"))
                    }
                }
            }
            // The menu bar item, rendered from the same view the status item hosts.
            for scheme in [ColorScheme.light, .dark] {
                let bar = MenuBarLabel(store: store)
                    .environment(\.colorScheme, scheme)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.93))
                let renderer = ImageRenderer(content: bar)
                renderer.scale = 3
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("menubar-\(scheme).png"))
                }
            }
            AppDefaults.clearDemo()
            exit(0)
        }
        RunLoop.main.run()
    }
}
