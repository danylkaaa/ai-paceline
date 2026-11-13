import AILimitsCore
import Charts
import SwiftUI

/// Two points further apart than this have no data between them and are joined by a dashed line.
private let maxGap: TimeInterval = 3 * 3600

private let solid = StrokeStyle(lineWidth: 2.2, lineCap: .round)
private let dashed = StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4])

/// This week's used % against even use, with earlier weeks in grey.
struct WeekChart: View {
    var provider: Provider
    var windows: [UsageWindow]
    var current: Limit
    var now: Date

    var body: some View {
        let reset = current.resetsAt ?? now
        let start = reset.addingTimeInterval(-current.windowSeconds)
        let past = windows.filter { $0.resetsAt < start.addingTimeInterval(3600) }.suffix(3)
        let saved = windows.last { abs($0.resetsAt.timeIntervalSince(reset)) < 3600 }?.points ?? []
        let currentLine = [ChartPoint(at: start, value: 0)]
            + saved.map { ChartPoint(at: $0.at, value: $0.usedPercent) }
            + [ChartPoint(at: now, value: current.usedPercent)]
        let color = Color(Palette.base(provider))

        VStack(alignment: .leading, spacing: 6) {
        Chart {
            ForEach([0.0, 7.0], id: \.self) { day in
                LineMark(x: .value("Day", day), y: .value("Used", day / 7 * 100), series: .value("Line", "even"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            ForEach(Array(past)) { w in
                let line = [ChartPoint(at: w.start, value: 0)] + w.points.map { ChartPoint(at: $0.at, value: $0.usedPercent) }
                ForEach(Segments.split(line, maxGap: maxGap)) { seg in
                    ForEach(seg.points, id: \.at) { p in
                        LineMark(x: .value("Day", days(p.at, from: w.start)), y: .value("Used", p.value),
                                 series: .value("Line", "past-\(w.resetsAt.timeIntervalSince1970)-\(seg.id)"))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                            .lineStyle(seg.dashed ? StrokeStyle(lineWidth: 1, dash: [3, 3]) : StrokeStyle(lineWidth: 1.2))
                    }
                }
            }

            ForEach(currentLine, id: \.at) { p in
                AreaMark(x: .value("Day", days(p.at, from: start)), y: .value("Used", p.value), series: .value("Line", "area"))
                    .foregroundStyle(color.opacity(0.15))
            }
            ForEach(Segments.split(currentLine, maxGap: maxGap)) { seg in
                ForEach(seg.points, id: \.at) { p in
                    LineMark(x: .value("Day", days(p.at, from: start)), y: .value("Used", p.value),
                             series: .value("Line", "now-\(seg.id)"))
                        .foregroundStyle(color)
                        .lineStyle(seg.dashed ? dashed : solid)
                }
            }
            PointMark(x: .value("Day", days(now, from: start)), y: .value("Used", current.usedPercent))
                .foregroundStyle(color)
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text("\(Int(current.usedPercent.rounded()))% used").font(.caption2.weight(.semibold))
                }
        }
        .chartXScale(domain: 0...7)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: Array(0...6).map(Double.init)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(anchor: .topLeading) {
                    if let d = value.as(Double.self) {
                        Text(start.addingTimeInterval(d * 86400).formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
            }
        }
        .frame(height: 140)
        HStack(spacing: 14) {
            LegendItem(label: "This week", color: color, style: StrokeStyle(lineWidth: 2.2))
            if !past.isEmpty {
                LegendItem(label: "Earlier weeks", color: .secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2))
            }
            LegendItem(label: "Even use", color: .secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        }
    }

    private func days(_ date: Date, from start: Date) -> Double {
        min(7, max(0, date.timeIntervalSince(start) / 86400))
    }
}

/// Both providers' weekly % left over the last 7 days: 100% at each reset, down towards 0%.
struct OverviewChart: View {
    var history: History
    var now: Date
    @ObservedObject var zoom: ChartZoom

    var body: some View {
        let range = zoom.range(endingAt: now)
        let from = range.lowerBound
        VStack(alignment: .leading, spacing: 6) {
        Chart {
            ForEach(Provider.allCases) { provider in
                ForEach(history.windows(provider).filter { $0.resetsAt > from && $0.start < range.upperBound }) { w in
                    ForEach(Segments.split(Self.visible(w.leftLine(now: now), from: from), maxGap: maxGap)) { seg in
                        ForEach(seg.points, id: \.at) { p in
                            LineMark(x: .value("Time", p.at), y: .value("Left", p.value),
                                     series: .value("Line", "\(provider.name)-\(w.resetsAt.timeIntervalSince1970)-\(seg.id)"))
                                .foregroundStyle(by: .value("Provider", provider.name))
                                .lineStyle(seg.dashed ? dashed : solid)
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale(["Claude": Color(Palette.base(.claude)), "Codex": Color(Palette.base(.codex))])
        .chartXScale(domain: range)
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            if zoom.days <= 2 {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.hour(), anchor: .topLeading)
                }
            } else if zoom.days <= 7 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .topLeading)
                }
            } else {
                AxisMarks(values: Self.dateTicks(range, every: zoom.days / 5)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), anchor: .topLeading)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 140)
        .zoomable(zoom)
        ZoomHint(zoom: zoom)
        }
    }

    /// Ticks spaced `every` days, kept clear of both ends so no label is cut off.
    private static func dateTicks(_ range: ClosedRange<Date>, every days: Double) -> [Date] {
        let step = days * 86400
        return Array(stride(from: range.lowerBound.addingTimeInterval(step / 2),
                            through: range.upperBound.addingTimeInterval(-step / 2), by: step))
    }

    /// Drops points before `from`, keeping one so the line enters the chart from its left edge.
    private static func visible(_ line: [ChartPoint], from: Date) -> [ChartPoint] {
        guard let firstInside = line.firstIndex(where: { $0.at >= from }) else { return [] }
        return Array(line[max(0, firstInside - 1)...])
    }
}

struct LegendItem: View {
    var label: String
    var color: Color
    var style: StrokeStyle

    var body: some View {
        HStack(spacing: 5) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                p.addLine(to: CGPoint(x: 16, y: 4))
            }
            .stroke(color, style: style)
            .frame(width: 16, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
