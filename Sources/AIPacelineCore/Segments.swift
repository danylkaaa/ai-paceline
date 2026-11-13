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
    /// Splits a sorted line into runs where neighbours are at most `maxGap` apart. Runs of two or more points are
    /// measured and drawn solid. The link between two such runs is a guess and drawn dashed; a link that touches a
    /// lone point (a reset, or one reading) is drawn solid.
    public static func split(_ points: [ChartPoint], maxGap: TimeInterval) -> [LineSegment] {
        var runs: [[ChartPoint]] = []
        for p in points {
            if let prev = runs.last?.last, p.at.timeIntervalSince(prev.at) <= maxGap {
                runs[runs.count - 1].append(p)
            } else {
                runs.append([p])
            }
        }
        var result: [LineSegment] = []
        for (i, run) in runs.enumerated() {
            if run.count > 1 { result.append(LineSegment(id: result.count, points: run, dashed: false)) }
            guard i + 1 < runs.count, let last = run.last, let first = runs[i + 1].first else { continue }
            let dashed = run.count > 1 && runs[i + 1].count > 1
            result.append(LineSegment(id: result.count, points: [last, first], dashed: dashed))
        }
        if result.isEmpty, let only = runs.first {
            result.append(LineSegment(id: 0, points: only, dashed: false))
        }
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
