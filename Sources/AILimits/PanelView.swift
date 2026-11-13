import AILimitsCore
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview", claude = "Claude", codex = "Codex"
    var id: String { rawValue }
    var provider: Provider? { self == .claude ? .claude : self == .codex ? .codex : nil }
}

struct PanelView: View {
    @ObservedObject var store: UsageStore
    var onResize: () -> Void = {}
    @AppStorage("tab") private var tab: Tab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview: OverviewTab(store: store)
            case .claude: ProviderTab(store: store, provider: .claude)
            case .codex: ProviderTab(store: store, provider: .codex)
            }

            Divider()
            Footer(store: store)
        }
        .padding(16)
        .frame(width: 440, alignment: .leading)
        .onChange(of: tab) { DispatchQueue.main.async(execute: onResize) }
    }
}

// MARK: - Overview

struct OverviewTab: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Provider.allCases) { provider in
                SummaryCard(provider: provider, status: store.status(provider), now: store.now)
            }
        }
    }
}

struct SummaryCard: View {
    var provider: Provider
    var status: ProviderStatus
    var now: Date

    var body: some View {
        let weekly = status.usage?.weekly
        let used = weekly?.usedPercent ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(provider.name).font(.headline)
                if let plan = status.usage?.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 12) {
                ZStack {
                    Ring(usedPercent: used, color: ringColor(provider, status, used), lineWidth: 6)
                    Text(weekly.map { "\(Int($0.leftPercent.rounded()))%" } ?? "–")
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text("left this week").font(.caption).foregroundStyle(.secondary)
                    if let reset = weekly?.resetsAt {
                        Text("resets in \(ResetText.long(until: reset, now: now))").font(.callout)
                    }
                    if let weekly, let pace = Pace.of(weekly, now: now) {
                        Text(PaceText.outlook(pace)).font(.caption).foregroundStyle(paceColor(pace))
                    }
                }
            }
            if let error = status.notLoggedIn ? UsageError.notLoggedIn(provider).localizedDescription : status.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Provider tab

struct ProviderTab: View {
    @ObservedObject var store: UsageStore
    var provider: Provider

    var body: some View {
        let status = store.status(provider)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(provider.name).font(.title3.weight(.semibold))
                if let plan = status.usage?.plan {
                    Text(plan).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(Palette.base(provider)).opacity(0.18), in: Capsule())
                }
            }
            if status.notLoggedIn {
                Notice(text: UsageError.notLoggedIn(provider).localizedDescription)
            } else if let error = status.error {
                Notice(text: status.usage == nil ? error : "\(error) Showing the last numbers.")
            }
            ForEach(status.usage?.limits ?? []) { limit in
                LimitRow(provider: provider, limit: limit, now: store.now, stale: status.error != nil)
            }
            if let shares = status.usage?.breakdown.filter({ $0.percent > 0 }), !shares.isEmpty {
                Section(title: "Where usage goes this week") { ShareBar(provider: provider, shares: shares) }
            }
        }
    }
}

struct LimitRow: View {
    var provider: Provider
    var limit: Limit
    var now: Date
    var stale: Bool

    var body: some View {
        let pace = Pace.of(limit, now: now)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title).font(.callout.weight(.medium))
                Spacer()
                Text("\(Int(limit.leftPercent.rounded()))% left").font(.callout.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(stale ? Color(Palette.unavailable) : Color(Palette.ring(provider, usedPercent: limit.usedPercent)))
                        .frame(width: max(6, geo.size.width * min(1, limit.usedPercent / 100)))
                    if let pace {
                        Rectangle().fill(.primary.opacity(0.75))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * pace.expectedPercent / 100 - 1)
                    }
                }
            }
            .frame(height: 8)
            HStack {
                if let pace { Text(PaceText.line(pace)).foregroundStyle(paceColor(pace)) }
                Spacer()
                if let reset = limit.resetsAt { Text("resets in \(ResetText.long(until: reset, now: now))") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct ShareBar: View {
    var provider: Provider
    var shares: [Share]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Rectangle().fill(shade(index))
                            .frame(width: max(3, (geo.size.width - CGFloat(shares.count - 1) * 2) * share.percent / 100))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    HStack(spacing: 4) {
                        Circle().fill(shade(index)).frame(width: 7, height: 7)
                        Text("\(share.name) \(Int(share.percent))%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func shade(_ index: Int) -> Color {
        Color(Palette.base(provider)).opacity(max(0.3, 1 - Double(index) * 0.3))
    }
}

// MARK: - Shared pieces

struct Section<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content
        }
    }
}

struct Notice: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Footer: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack {
            if let last = store.lastRefresh {
                Text("Updated \(last.formatted(.relative(presentation: .named)))")
            } else {
                Text("Loading…")
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: store.refreshing)
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(store.refreshing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

enum PaceText {
    static func line(_ pace: Pace) -> String {
        let delta = Int(pace.deltaPercent.rounded())
        let where_ = delta > 2 ? "\(delta)% over pace" : delta < -2 ? "\(-delta)% in reserve" : "on pace"
        return "\(where_) · \(outlook(pace))"
    }

    static func outlook(_ pace: Pace) -> String {
        guard let at = pace.runsOutAt else { return "lasts until reset" }
        return "runs out \(at.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}

func paceColor(_ pace: Pace) -> Color {
    pace.runsOutAt != nil ? .red : pace.deltaPercent > 2 ? .orange : .secondary
}

func ringColor(_ provider: Provider, _ status: ProviderStatus, _ used: Double) -> Color {
    Color(status.error == nil && status.usage != nil ? Palette.ring(provider, usedPercent: used) : Palette.unavailable)
}
