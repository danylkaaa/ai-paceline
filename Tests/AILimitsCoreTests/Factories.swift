import Foundation
@testable import AILimitsCore

enum Fixed {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let reset1 = 1_800_100_000.0
    static let reset2 = 1_800_200_000.0
    static let renewsAt = "2027-02-01T00:00:00Z"
    static let activeUntil = "2027-03-01T00:00:00Z"
}

enum Factories {
    static func limit(usedPercent: Double = 40, resetsAt: Date? = Fixed.t0.addingTimeInterval(100), windowSeconds: TimeInterval = 200) -> Limit {
        Limit(id: Limit.weeklyID, title: "Weekly", usedPercent: usedPercent, resetsAt: resetsAt, windowSeconds: windowSeconds)
    }

    /// A line starting at t0; each gap is the seconds between two neighbouring points.
    static func chartLine(gaps: [TimeInterval]) -> [ChartPoint] {
        var at = Fixed.t0
        var points = [ChartPoint(at: at, value: 0)]
        for (i, gap) in gaps.enumerated() {
            at = at.addingTimeInterval(gap)
            points.append(ChartPoint(at: at, value: Double(i + 1)))
        }
        return points
    }

    static func historyPoint(at: Date, usedPercent: Double, resetsAt: Date = Fixed.t0.addingTimeInterval(86400)) -> HistoryPoint {
        HistoryPoint(provider: .claude, at: at, usedPercent: usedPercent, resetsAt: resetsAt)
    }

    static func window(resetsAt: Date, windowSeconds: TimeInterval = 7 * 86400, points: [HistoryPoint]) -> UsageWindow {
        UsageWindow(start: resetsAt.addingTimeInterval(-windowSeconds), resetsAt: resetsAt, points: points)
    }

    // MARK: dates, files, JSON

    static func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: text) else { fatalError("bad date \(text)") }
        return date
    }

    static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: history

    static func point(_ provider: Provider = .claude, at: Date, usedPercent: Double = 10, resetsAt: Date? = nil) -> HistoryPoint {
        HistoryPoint(provider: provider, at: at, usedPercent: usedPercent, resetsAt: resetsAt ?? at.addingTimeInterval(86400))
    }

    static func namedLimit(id: String, usedPercent: Double = 10, resetsAt: Date? = nil, windowSeconds: TimeInterval = 18000) -> Limit {
        Limit(id: id, title: id, usedPercent: usedPercent, resetsAt: resetsAt, windowSeconds: windowSeconds)
    }

    static func usage(_ provider: Provider = .claude, fetchedAt: Date = Fixed.t0, limits: [Limit]) -> ProviderUsage {
        ProviderUsage(provider: provider, plan: nil, limits: limits, fetchedAt: fetchedAt)
    }

    // MARK: Claude payloads

    static func claudeUsageJSON(fiveHour: (used: Double?, resetsAt: String?)? = nil,
                                sevenDay: (used: Double?, resetsAt: String?)? = nil,
                                rows: [[String: Any]] = [],
                                breakdown: [(name: String, percent: Double)]? = nil) -> Data {
        func window(_ w: (used: Double?, resetsAt: String?)) -> [String: Any] {
            ["utilization": w.used ?? NSNull(), "resets_at": w.resetsAt ?? NSNull()]
        }
        var root: [String: Any] = ["limits": rows]
        if let fiveHour { root["five_hour"] = window(fiveHour) }
        if let sevenDay { root["seven_day"] = window(sevenDay) }
        if let breakdown {
            root["seven_day_breakdown"] = ["rows": breakdown.map { ["display_name": $0.name, "percent": $0.percent] }]
        }
        return json(root)
    }

    static func claudeRow(kind: String, percent: Double? = nil, resetsAt: String? = nil, model: String? = nil) -> [String: Any] {
        var row: [String: Any] = ["kind": kind]
        if let percent { row["percent"] = percent }
        if let resetsAt { row["resets_at"] = resetsAt }
        if let model { row["scope"] = ["model": ["display_name": model]] }
        return row
    }

    static func claudeCredentialsJSON(token: String, expiresAtMs: Double? = nil, tier: String? = nil, subscription: String? = nil) -> Data {
        var oauth: [String: Any] = ["accessToken": token]
        if let expiresAtMs { oauth["expiresAt"] = expiresAtMs }
        if let tier { oauth["rateLimitTier"] = tier }
        if let subscription { oauth["subscriptionType"] = subscription }
        return json(["claudeAiOauth": oauth])
    }

    static func claudeProfileJSON(planLabel: String? = nil, subscriptionCreatedAt: String? = nil) -> Data {
        var org: [String: Any] = [:]
        if let planLabel { org["plan_display_label"] = planLabel }
        if let subscriptionCreatedAt { org["subscription_created_at"] = subscriptionCreatedAt }
        return json(["organization": org])
    }

    // MARK: Codex payloads

    static func codexUsageWindow(used: Double, seconds: Double, resetAt: Double? = nil) -> [String: Any] {
        var w: [String: Any] = ["used_percent": used, "limit_window_seconds": seconds]
        if let resetAt { w["reset_at"] = resetAt }
        return w
    }

    static func codexUsageJSON(plan: String? = nil, primary: [String: Any]? = nil, secondary: [String: Any]? = nil) -> Data {
        var rateLimit: [String: Any] = [:]
        if let primary { rateLimit["primary_window"] = primary }
        if let secondary { rateLimit["secondary_window"] = secondary }
        var root: [String: Any] = ["rate_limit": rateLimit]
        if let plan { root["plan_type"] = plan }
        return json(root)
    }

    static func codexLogWindow(minutes: Double? = nil, used: Double? = nil, resetsAt: Double? = nil) -> [String: Any] {
        var w: [String: Any] = [:]
        if let minutes { w["window_minutes"] = minutes }
        if let used { w["used_percent"] = used }
        if let resetsAt { w["resets_at"] = resetsAt }
        return w
    }

    static func codexLogLine(timestamp: String? = nil, planType: String? = nil,
                             primary: [String: Any]? = nil, secondary: [String: Any]? = nil) -> String {
        var rateLimits: [String: Any] = [:]
        if let planType { rateLimits["plan_type"] = planType }
        if let primary { rateLimits["primary"] = primary }
        if let secondary { rateLimits["secondary"] = secondary }
        var root: [String: Any] = ["payload": ["rate_limits": rateLimits]]
        if let timestamp { root["timestamp"] = timestamp }
        return text(json(root))
    }

    // MARK: token usage payloads

    static func claudeInstancesJSON(projects: [String: [[String: Any]]]) -> Data {
        json(["projects": projects])
    }

    static func claudeDay(_ date: String, _ models: [[String: Any]]) -> [String: Any] {
        ["date": date, "modelBreakdowns": models]
    }

    static func modelRow(_ name: String, input: Double = 0, output: Double = 0, cacheCreation: Double = 0,
                         cacheRead: Double = 0, cost: Double = 0) -> [String: Any] {
        ["modelName": name, "inputTokens": input, "outputTokens": output,
         "cacheCreationTokens": cacheCreation, "cacheReadTokens": cacheRead, "cost": cost]
    }

    static func codexDailyJSON(days: [(date: String, costUSD: Double?, models: [String: Double])]) -> Data {
        json(["daily": days.map { day -> [String: Any] in
            var row: [String: Any] = ["date": day.date,
                                      "models": day.models.mapValues { ["totalTokens": $0] }]
            if let cost = day.costUSD { row["costUSD"] = cost }
            return row
        }])
    }
}
