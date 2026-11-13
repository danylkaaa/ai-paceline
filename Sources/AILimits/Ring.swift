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

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Provider.allCases) { provider in
                if let weekly = store.status(provider).usage?.weekly {
                    HStack(spacing: 4) {
                        Ring(usedPercent: weekly.usedPercent,
                             color: Color(Palette.ring(provider, usedPercent: weekly.usedPercent)))
                            .frame(width: 15, height: 15)
                        if let reset = weekly.resetsAt {
                            Text(ResetText.short(until: reset, now: store.now))
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .fixedSize()
    }
}
