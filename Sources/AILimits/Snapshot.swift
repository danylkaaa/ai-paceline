import AppKit
import SwiftUI

/// `AILimits --snapshot <dir>`: fetches real data, writes one PNG per tab, and exits. Used to check the UI.
@MainActor
enum Snapshot {
    static func run(into dir: URL) {
        let store = UsageStore()
        Task {
            await store.refresh()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for scheme in [ColorScheme.dark, .light] {
                for tab in Tab.allCases {
                    UserDefaults.standard.set(tab.rawValue, forKey: "tab")
                    let view = PanelView(store: store)
                        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("\(tab.rawValue.lowercased())-\(scheme).png"))
                    }
                }
            }
            exit(0)
        }
        RunLoop.main.run()
    }
}
