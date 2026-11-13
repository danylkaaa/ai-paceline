import AILimitsCore
import Charts
import SwiftUI

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
        Chart {
            ForEach([0.0, 7.0], id: \.self) { day in
                LineMark(x: .value("Day", day), y: .value("Used", day / 7 * 100), series: .value("Line", "Even use"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(Array(past)) { w in
                ForEach(line(w.points, start: w.start)) { pt in
                    LineMark(x: .value("Day", pt.day), y: .value("Used", pt.used), series: .value("Line", "w\(w.resetsAt)"))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }

            let points = line(windows.last { abs($0.resetsAt.timeIntervalSince(reset)) < 3600 }?.points ?? [], start: start)
                + [DayPoint(day: days(now, from: start), used: current.usedPercent)]
            ForEach(points) { pt in
                AreaMark(x: .value("Day", pt.day), y: .value("Used", pt.used), series: .value("Line", "now"))
                    .foregroundStyle(Color(Palette.base(provider)).opacity(0.15))
                LineMark(x: .value("Day", pt.day), y: .value("Used", pt.used), series: .value("Line", "now"))
                    .foregroundStyle(Color(Palette.base(provider)))
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.day), y: .value("Used", last.used))
                    .foregroundStyle(Color(Palette.base(provider)))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text("\(Int(last.used.rounded()))%").font(.caption2.weight(.semibold))
                    }
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
    }

    private func line(_ points: [HistoryPoint], start: Date) -> [DayPoint] {
        [DayPoint(day: 0, used: 0)] + points.map { DayPoint(day: days($0.at, from: start), used: $0.usedPercent) }
    }

    private func days(_ date: Date, from start: Date) -> Double {
        min(7, max(0, date.timeIntervalSince(start) / 86400))
    }
}

struct DayPoint: Identifiable {
    var day: Double
    var used: Double
    var id: Double { day }
}

/// Both providers' weekly % over the last 7 days.
struct OverviewChart: View {
    var history: History
    var now: Date

    var body: some View {
        let from = now.addingTimeInterval(-7 * 86400)
        Chart {
            ForEach(Provider.allCases) { provider in
                ForEach(history.windows(provider).filter { $0.resetsAt > from }) { w in
                    ForEach(Self.line(w, from: from, now: now), id: \.at) { p in
                        LineMark(x: .value("Time", p.at), y: .value("Used", p.usedPercent),
                                 series: .value("Window", "\(provider.name)-\(w.resetsAt.timeIntervalSince1970)"))
                            .foregroundStyle(by: .value("Provider", provider.name))
                    }
                }
            }
        }
        .chartForegroundStyleScale(["Claude": Color(Palette.base(.claude)), "Codex": Color(Palette.base(.codex))])
        .chartXScale(domain: from...now)
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .topLeading)
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
    }

    /// A window starts at 0% and, once over, keeps its last value until its reset (usage never drops inside a window).
    /// The chart clips the part before `from`.
    private static func line(_ w: UsageWindow, from: Date, now: Date) -> [HistoryPoint] {
        guard let last = w.points.last else { return [] }
        var all = [HistoryPoint(provider: last.provider, at: w.start, usedPercent: 0, resetsAt: w.resetsAt)] + w.points
        if w.resetsAt < now {
            all.append(HistoryPoint(provider: last.provider, at: w.resetsAt, usedPercent: last.usedPercent, resetsAt: w.resetsAt))
        }
        guard let firstInside = all.firstIndex(where: { $0.at >= from }) else { return [] }
        return Array(all[max(0, firstInside - 1)...])
    }
}
