import AppKit

let app = NSApplication.shared
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
        let store = UsageStore()
        self.store = store
        status = StatusController(store: store)
        store.start()
    }
}
