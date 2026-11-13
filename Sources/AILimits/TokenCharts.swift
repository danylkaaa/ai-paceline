import AILimitsCore
import Charts
import SwiftUI

enum Metric: String, CaseIterable, Identifiable {
    case tokens = "Tokens", cost = "Cost"
    var id: String { rawValue }
}

struct TokenSection: View {
    @ObservedObject var store: UsageStore
    var provider: Provider
    @AppStorage("metric") private var metric: Metric = .tokens

    var body: some View {
        if let usage = store.tokens[provider] {
            Section(title: "Last 30 days") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Stat(label: "Tokens", value: Fmt.tokens(usage.totalTokens))
                        Stat(label: "Est. API cost", value: Fmt.money(usage.totalCost))
                        Spacer()
                        Picker("", selection: $metric) {
                            ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    DailyChart(provider: provider, usage: usage, metric: metric)
                    Text("Cost is tokens × public API prices, not your bill.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !usage.projects.isEmpty {
                Section(title: "Top projects") { ProjectList(provider: provider, projects: usage.projects) }
            }
        } else if let error = store.tokenErrors[provider] {
            Notice(text: error)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading token history…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DailyChart: View {
    var provider: Provider
    var usage: TokenUsage
    var metric: Metric

    var body: some View {
        let models = modelsByVolume
        Chart(usage.daily) { row in
            BarMark(x: .value("Day", row.day, unit: .day),
                    y: .value(metric.rawValue, metric == .tokens ? row.tokens : row.cost))
                .foregroundStyle(by: .value("Model", seriesName(row.model)))
                .cornerRadius(2)
        }
        .chartForegroundStyleScale(domain: models, range: models.indices.map { Color(Palette.series(provider, index: $0)) })
        .chartXScale(domain: firstDay...lastDay.addingTimeInterval(86400))
        .chartXAxis {
            AxisMarks(values: [27, 20, 13, 6].map { lastDay.addingTimeInterval(-Double($0) * 86400) }) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .tokens ? Fmt.tokens(v) : Fmt.money(v, short: true))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        .frame(height: 170)
    }

    /// Codex reports cost per day only, so the cost view shows one series.
    private func seriesName(_ model: String) -> String {
        metric == .cost && !usage.costPerModel ? "All models" : model
    }

    private var modelsByVolume: [String] {
        var totals: [String: Double] = [:]
        for row in usage.daily { totals[seriesName(row.model), default: 0] += metric == .tokens ? row.tokens : row.cost }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }

    private var lastDay: Date { Calendar.current.startOfDay(for: Date()) }
    private var firstDay: Date { lastDay.addingTimeInterval(-29 * 86400) }
}

struct ProjectList: View {
    var provider: Provider
    var projects: [ProjectUsage]

    var body: some View {
        let top = Array(projects.prefix(5))
        let maxCost = top.first?.cost ?? 1
        VStack(alignment: .leading, spacing: 8) {
            ForEach(top) { p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text("\(Fmt.money(p.cost)) · \(Fmt.tokens(p.tokens))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Color(Palette.base(provider)).opacity(0.7))
                            .frame(width: max(3, geo.size.width * p.cost / max(maxCost, 0.01)))
                    }
                    .frame(height: 4)
                    Text(Fmt.home(p.path)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
}

struct Stat: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.trailing, 14)
    }
}

enum Fmt {
    static func tokens(_ v: Double) -> String {
        switch v {
        case 1e9...: return String(format: "%.1fB", v / 1e9)
        case 1e6...: return String(format: "%.0fM", v / 1e6)
        case 1e3...: return String(format: "%.0fK", v / 1e3)
        default: return String(format: "%.0f", v)
        }
    }

    static func money(_ v: Double, short: Bool = false) -> String {
        short || v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    static func home(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
