import Foundation

public enum ResetText {
    /// One unit, rounded down: "2d", "15h", "40m".
    public static func short(until date: Date, now: Date) -> String {
        let minutes = Int(max(0, date.timeIntervalSince(now)) / 60)
        if minutes >= 1440 { return "\(minutes / 1440)d" }
        if minutes >= 60 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    /// Two units: "2d 15h", "3h 20m", "40m".
    public static func long(until date: Date, now: Date) -> String {
        let minutes = Int(max(0, date.timeIntervalSince(now)) / 60)
        let d = minutes / 1440, h = (minutes % 1440) / 60, m = minutes % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

public struct RGB: Sendable, Hashable {
    public var r: Double, g: Double, b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
}

public enum Palette {
    public static let unavailable = RGB(hex: 0x8E8E93)

    /// Base color of a provider, used for charts.
    public static func base(_ provider: Provider) -> RGB {
        provider == .claude ? RGB(hex: 0xD97757) : RGB(hex: 0x2A9D8F)
    }

    /// Chart series colors: distinct hues inside the provider's family, most used first.
    public static func series(_ provider: Provider, index: Int) -> RGB {
        let colors: [UInt32] = provider == .claude
            ? [0xD97757, 0xE8B04B, 0xB5487A, 0x8C5A3C, 0xF2B48F]
            : [0x2A9D8F, 0x4A90D9, 0x7FCDBB, 0x5B6CC2, 0x9ED9F0]
        return RGB(hex: colors[index % colors.count])
    }

    /// Ring color: light below 50% used, base up to 80%, deep above.
    public static func ring(_ provider: Provider, usedPercent: Double) -> RGB {
        let steps: [UInt32] = provider == .claude
            ? [0xF2B48F, 0xD97757, 0xB83A1E]
            : [0x8FD9CC, 0x2A9D8F, 0x12676B]
        let index = usedPercent < 50 ? 0 : usedPercent < 80 ? 1 : 2
        return RGB(hex: steps[index])
    }
}
