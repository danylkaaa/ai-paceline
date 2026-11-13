import AIPacelineCore
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
        Group {
            if Provider.allCases.contains(where: visible) {
                // One bar per provider, Claude on top: the fill is the weekly limit used.
                VStack(spacing: 3) {
                    ForEach(Provider.allCases.filter(visible)) { provider in
                        let status = store.status(provider)
                        let used = status.usage?.weekly?.usedPercent ?? 0
                        LevelBar(usedPercent: used,
                                 color: Color(status.error == nil ? Palette.ring(provider, usedPercent: used) : Palette.unavailable))
                    }
                }
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 14))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .fixedSize()
    }
}

struct LevelBar: View {
    var usedPercent: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(0.22))
            Capsule().fill(color).frame(width: max(3, 22 * min(1, usedPercent / 100)))
        }
        .frame(width: 22, height: 4)
    }
}
