import AILimitsCore
import ServiceManagement
import SwiftUI

enum Settings {
    static let refreshMinutes = "refreshMinutes"
    static let refreshChoices = [5, 15, 30, 60]

    static func shows(_ provider: Provider) -> String { "show-\(provider.rawValue)" }

    static func register() {
        UserDefaults.standard.register(defaults: [
            refreshMinutes: 15,
            shows(.claude): true,
            shows(.codex): true,
        ])
    }
}

/// Panel UI state; `@State` needs the SwiftUI macro plugin, which the Command Line Tools do not ship.
@MainActor
final class PanelState: ObservableObject {
    @Published var showSettings = false
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginNote: String?
}

struct SettingsView: View {
    @ObservedObject var ui: PanelState
    @AppStorage(Settings.refreshMinutes) private var refreshMinutes = 15
    @AppStorage(Settings.shows(.claude)) private var showClaude = true
    @AppStorage(Settings.shows(.codex)) private var showCodex = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title3.weight(.semibold))

            Picker("Refresh every", selection: $refreshMinutes) {
                ForEach(Settings.refreshChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .frame(width: 260)

            VStack(alignment: .leading, spacing: 6) {
                Text("Show in menu bar").font(.callout)
                Toggle("Claude", isOn: $showClaude)
                Toggle("Codex", isOn: $showCodex)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Start at login", isOn: $ui.startAtLogin)
                    .onChange(of: ui.startAtLogin) { setStartAtLogin($1) }
                if let note = ui.loginNote { Text(note).font(.caption).foregroundStyle(.orange) }
            }

            Button("Quit AI Limits") { NSApp.terminate(nil) }
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            ui.loginNote = SMAppService.mainApp.status == .requiresApproval
                ? "Allow AI Limits in System Settings → General → Login Items." : nil
        } catch {
            ui.loginNote = "Could not change: \(error.localizedDescription)"
            log.error("login item change failed error=\(String(describing: error), privacy: .public)")
        }
    }
}
