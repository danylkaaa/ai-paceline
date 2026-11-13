import Foundation

/// Where usage stands against even use over the limit's window.
public struct Pace: Sendable, Equatable {
    /// Percent you would have used with even use until now.
    public var expectedPercent: Double
    /// Used minus expected: positive means faster than even use.
    public var deltaPercent: Double
    /// When the limit runs out at the current rate; nil when it lasts until reset.
    public var runsOutAt: Date?

    public static func of(_ limit: Limit, now: Date) -> Pace? {
        guard let reset = limit.resetsAt, limit.windowSeconds > 0 else { return nil }
        let start = reset.addingTimeInterval(-limit.windowSeconds)
        let elapsed = min(max(0, now.timeIntervalSince(start)), limit.windowSeconds)
        let expected = elapsed / limit.windowSeconds * 100
        var runsOut: Date?
        if limit.usedPercent >= 100 {
            runsOut = now
        } else if limit.usedPercent > 0, elapsed > 0 {
            let secondsLeft = (100 - limit.usedPercent) / (limit.usedPercent / elapsed)
            let at = now.addingTimeInterval(secondsLeft)
            if at < reset { runsOut = at }
        }
        return Pace(expectedPercent: expected, deltaPercent: limit.usedPercent - expected, runsOutAt: runsOut)
    }
}
