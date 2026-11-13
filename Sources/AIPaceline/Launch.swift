import AppKit

/// Command-line flags.
/// - `--demo`: made-up data; reads no account, writes no history and no settings.
/// - `--open overview|claude|codex|settings`: opens the panel at launch and keeps it open (for screenshots).
/// - `--appearance light|dark`: forces the panel's appearance.
enum Launch {
    static let arguments = CommandLine.arguments
    static let demo = arguments.contains("--demo")
    static let open = value(of: "--open")
    static let appearance = value(of: "--appearance")

    private static func value(of flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

/// Settings storage. Demo mode uses its own domain, emptied at start and at quit, so it never touches real settings.
enum AppDefaults {
    static let demoSuite = (Bundle.main.bundleIdentifier ?? "io.github.danylkaaa.aipaceline") + ".demo"
    /// UserDefaults is thread-safe; Apple documents it as safe to use from any thread.
    nonisolated(unsafe) static let store: UserDefaults = Launch.demo ? UserDefaults(suiteName: demoSuite) ?? .standard : .standard

    static func clearDemo() {
        guard Launch.demo else { return }
        UserDefaults.standard.removePersistentDomain(forName: demoSuite)
        // The domain removal leaves an empty file behind; demo mode keeps nothing.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(demoSuite).plist")
        try? FileManager.default.removeItem(at: file)
    }
}
