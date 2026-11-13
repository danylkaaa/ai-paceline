import AppKit

let app = NSApplication.shared
Settings.register()
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch Launch.appearance {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let store = UsageStore()
        self.store = store
        let status = StatusController(store: store)
        self.status = status
        store.start()
        if let target = Launch.open {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { status.openForScreenshot(target) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDefaults.clearDemo()
    }
}
