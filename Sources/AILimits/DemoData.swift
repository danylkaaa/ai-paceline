import AILimitsCore
import Foundation

/// Made-up data for `--demo`: stable across runs, so screenshots do not change, and free of real names.
enum DemoData {
    /// Invented project folders, checked not to be GitHub accounts.
    static let projects = ["quillfern", "brambleway", "copperwick", "lanternmoss", "tidelark"]

    static func claude(now: Date) -> ProviderUsage {
        let reset = nextReset(after: now, weekday: 2, hour: 9)
        return ProviderUsage(
            provider: .claude, plan: "Max",
            limits: [
                Limit(id: "session", title: "Session (5 h)", usedPercent: 22, resetsAt: now.addingTimeInterval(2.4 * 3600),
                      windowSeconds: 5 * 3600),
                Limit(id: Limit.weeklyID, title: "Week, all models", usedPercent: 46, resetsAt: reset, windowSeconds: 7 * 86400),
                Limit(id: "weekly-opus", title: "Week, Opus", usedPercent: 31, resetsAt: reset, windowSeconds: 7 * 86400),
            ],
            breakdown: [Share(name: "Claude Code", percent: 88), Share(name: "Chats", percent: 9), Share(name: "Cowork", percent: 3)],
            fetchedAt: now, renewsAt: day(now, plus: 9))
    }

    static func codex(now: Date) -> ProviderUsage {
        ProviderUsage(
            provider: .codex, plan: "Plus",
            limits: [
                Limit(id: "session", title: "Session (5 h)", usedPercent: 12, resetsAt: now.addingTimeInterval(3.1 * 3600),
                      windowSeconds: 5 * 3600),
                Limit(id: Limit.weeklyID, title: "Week", usedPercent: 28,
                      resetsAt: nextReset(after: now, weekday: 4, hour: 14), windowSeconds: 7 * 86400),
            ],
            fetchedAt: now, renewsAt: day(now, plus: 17))
    }

    /// Four weeks of weekly % per provider, one point every 3 hours while "working".
    static func history(now: Date) -> History {
        var history = History()
        for (provider, usage, weekday, hour) in [(Provider.claude, claude(now: now), 2, 9), (.codex, codex(now: now), 4, 14)] {
            var random = Seeded(provider == .claude ? 7 : 11)
            let finalUsed = usage.weekly?.usedPercent ?? 0
            var reset = nextReset(after: now, weekday: weekday, hour: hour)
            for week in 0..<4 {
                let start = reset.addingTimeInterval(-7 * 86400)
                let target = week == 0 ? finalUsed : 55 + random.next() * 35
                let end = week == 0 ? now : reset
                var t = start.addingTimeInterval(3600), used = 0.0
                let span = end.timeIntervalSince(start)
                while t < end {
                    let hourOfDay = Calendar.current.component(.hour, from: t)
                    if (9...23).contains(hourOfDay) {
                        used = min(target, max(used, target * t.timeIntervalSince(start) / span + random.next() * 3 - 1.5))
                        history.add(HistoryPoint(provider: provider, at: t, usedPercent: used.rounded(), resetsAt: reset))
                    }
                    t.addTimeInterval(3 * 3600)
                }
                reset = start
            }
            history.add(HistoryPoint(provider: provider, at: now, usedPercent: finalUsed,
                                     resetsAt: nextReset(after: now, weekday: weekday, hour: hour)))
            history.record(usage)
        }
        return history
    }

    static func tokens(_ provider: Provider, now: Date) -> TokenUsage {
        var random = Seeded(provider == .claude ? 3 : 5)
        let models: [(String, Double, Double)] = provider == .claude
            ? [("Opus 4.5", 1.0, 0.000_000_6), ("Sonnet 4.5", 0.55, 0.000_000_3), ("Haiku 4.5", 0.12, 0.000_000_1)]
            : [("gpt-5-codex", 1.0, 0.000_000_2), ("gpt-5", 0.3, 0.000_000_2)]
        let scale = provider == .claude ? 260e6 : 40e6
        let today = Calendar.current.startOfDay(for: now)
        var daily: [DailyModelUsage] = []
        for back in 0..<60 {
            let day = today.addingTimeInterval(-Double(back) * 86400)
            let weekday = Calendar.current.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7
            let busy = (weekend ? 0.25 : 1.0) * (0.35 + random.next()) * (1 + Double(60 - back) / 90)
            for (name, share, price) in models {
                let tokens = scale * busy * share * (0.6 + random.next() * 0.8)
                daily.append(DailyModelUsage(day: day, model: name, tokens: tokens, cost: tokens * price))
            }
        }
        let total = daily.reduce(0) { $0 + $1.tokens }
        let weights = [0.38, 0.24, 0.17, 0.12, 0.09]
        let projects = provider == .claude
            ? zip(projects, weights).map { name, w in
                ProjectUsage(name: name, path: "~/Projects/\(name)", tokens: total * w,
                             cost: daily.reduce(0) { $0 + $1.cost } * w)
            }
            : []
        return TokenUsage(daily: daily.sorted { ($0.day, $0.model) < ($1.day, $1.model) }, projects: projects,
                          costPerModel: provider == .claude)
    }

    private static func nextReset(after now: Date, weekday: Int, hour: Int) -> Date {
        Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0, weekday: weekday),
                                  matchingPolicy: .nextTime) ?? now.addingTimeInterval(3 * 86400)
    }

    private static func day(_ now: Date, plus days: Double) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(days * 86400)
    }
}

/// Small deterministic generator (SplitMix64), so demo data is the same on every run.
private struct Seeded {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
