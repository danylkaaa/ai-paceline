import AIPacelineCore
import ServiceManagement
import SwiftUI

enum Settings {
    static let refreshMinutes = "refreshMinutes"
    static let refreshChoices = [5, 15, 30, 60]

    static func shows(_ provider: Provider) -> String { "show-\(provider.rawValue)" }
    static func price(_ provider: Provider) -> String { "price-\(provider.rawValue)" }

    static func register() {
        AppDefaults.clearDemo()
        AppDefaults.store.register(defaults: [
            refreshMinutes: 15,
            shows(.claude): true,
            shows(.codex): true,
            // Prices are not reported by either server; 0 hides them until set in Settings.
            price(.claude): Launch.demo ? 100.0 : 0.0,
            price(.codex): Launch.demo ? 20.0 : 0.0,
        ])
    }
}

/// Panel UI state; `@State` needs the SwiftUI macro plugin, which the Command Line Tools do not ship.
@MainActor
final class PanelState: ObservableObject {
    @Published var showSettings = false
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginNote: String?
    @Published var contentHeight: CGFloat = 300
    @Published var maxPanelHeight: CGFloat = 800
    let overviewZoom = ChartZoom(levels: [1, 2, 3, 7, 14, 30, 60], initial: 7)
    let tokenZoom: [Provider: ChartZoom] = Dictionary(uniqueKeysWithValues: Provider.allCases.map {
        ($0, ChartZoom(levels: [7, 14, 30, 60], initial: 30))
    })
    /// Off only for snapshots: ImageRenderer does not draw ScrollView contents.
    var scrolls = true
}

struct SettingsView: View {
    @ObservedObject var ui: PanelState
    @AppStorage(Settings.refreshMinutes, store: AppDefaults.store) private var refreshMinutes = 15
    @AppStorage(Settings.shows(.claude)) private var showClaude = true
    @AppStorage(Settings.shows(.codex)) private var showCodex = true
    @AppStorage(Settings.price(.claude)) private var claudePrice = 240.0
    @AppStorage(Settings.price(.codex)) private var codexPrice = 22.0

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Monthly price (servers do not report it)").font(.callout)
                PriceField(label: "Claude", value: $claudePrice)
                PriceField(label: "ChatGPT", value: $codexPrice)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Start at login", isOn: $ui.startAtLogin)
                    .onChange(of: ui.startAtLogin) { setStartAtLogin($1) }
                if let note = ui.loginNote { Text(note).font(.caption).foregroundStyle(.orange) }
            }

            Button("Quit AI Paceline") { NSApp.terminate(nil) }
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setStartAtLogin(_ on: Bool) {
        guard !Launch.demo else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            ui.loginNote = SMAppService.mainApp.status == .requiresApproval
                ? "Allow AI Paceline in System Settings → General → Login Items." : nil
        } catch {
            ui.loginNote = "Could not change: \(error.localizedDescription)"
            log.error("login item change failed error=\(String(describing: error), privacy: .public)")
        }
    }
}

struct PriceField: View {
    var label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("", value: $value, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            Text("/ month").foregroundStyle(.secondary)
        }
    }
}
