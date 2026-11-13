import Foundation

public struct ChartPoint: Sendable, Hashable {
    public var at: Date
    public var value: Double

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

/// A run of points drawn as one line; `dashed` marks a stretch with no data in between.
public struct LineSegment: Sendable, Identifiable {
    public var id: Int
    public var points: [ChartPoint]
    public var dashed: Bool
}

public enum Segments {
    /// Splits a sorted line into solid runs and dashed bridges where two points are more than `maxGap` apart.
    public static func split(_ points: [ChartPoint], maxGap: TimeInterval) -> [LineSegment] {
        guard var run = points.first.map({ [$0] }) else { return [] }
        var result: [LineSegment] = []
        for p in points.dropFirst() {
            let prev = run[run.count - 1]
            if p.at.timeIntervalSince(prev.at) > maxGap {
                if run.count > 1 { result.append(LineSegment(id: result.count, points: run, dashed: false)) }
                result.append(LineSegment(id: result.count, points: [prev, p], dashed: true))
                run = [p]
            } else {
                run.append(p)
            }
        }
        if run.count > 1 || result.isEmpty { result.append(LineSegment(id: result.count, points: run, dashed: false)) }
        return result
    }
}

extension UsageWindow {
    /// The window as "% left" over time: 100% at its start, each saved point, and (once over) its last value
    /// held until the reset, since usage cannot drop inside a window.
    public func leftLine(now: Date) -> [ChartPoint] {
        guard let last = points.last else { return [] }
        var line = [ChartPoint(at: start, value: 100)] + points.map { ChartPoint(at: $0.at, value: max(0, 100 - $0.usedPercent)) }
        if resetsAt < now { line.append(ChartPoint(at: resetsAt, value: max(0, 100 - last.usedPercent))) }
        return line
    }
}
