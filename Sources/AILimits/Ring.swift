import AILimitsCore
import SwiftUI

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

struct Ring: View {
    var usedPercent: Double
    var color: Color
    var lineWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, usedPercent / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(Settings.shows(.claude)) private var showClaude = true
    @AppStorage(Settings.shows(.codex)) private var showCodex = true

    private func visible(_ provider: Provider) -> Bool {
        let status = store.status(provider)
        let wanted = provider == .claude ? showClaude : showCodex
        return wanted && !status.notLoggedIn && (status.usage != nil || status.error != nil)
    }

    var body: some View {
        HStack(spacing: 9) {
            if !Provider.allCases.contains(where: visible) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 14))
            }
            ForEach(Provider.allCases) { provider in
                let status = store.status(provider)
                if visible(provider) {
                    let weekly = status.usage?.weekly
                    let used = weekly?.usedPercent ?? 0
                    HStack(spacing: 4) {
                        Ring(usedPercent: used,
                             color: Color(status.error == nil ? Palette.ring(provider, usedPercent: used) : Palette.unavailable))
                            .frame(width: 15, height: 15)
                        Text(weekly?.resetsAt.map { ResetText.short(until: $0, now: store.now) } ?? "–")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .fixedSize()
    }
}
