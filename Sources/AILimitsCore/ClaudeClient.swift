import Foundation

public struct ClaudeCredentials: Sendable {
    public var accessToken: String
    public var expiresAt: Date?
    public var plan: String?

    /// Parses the JSON that Claude Code keeps in the Keychain item "Claude Code-credentials".
    public static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCredentials(accessToken: token, expiresAt: expires,
                                 plan: planName(tier: oauth["rateLimitTier"] as? String,
                                                subscription: oauth["subscriptionType"] as? String))
    }

    /// "default_claude_max_5x" → "Max 5x"; falls back to the subscription type.
    static func planName(tier: String?, subscription: String?) -> String? {
        if let tier, let range = tier.range(of: #"(max|pro|team|enterprise|ultra)(_\d+x)?$"#, options: .regularExpression) {
            return tier[range].split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return subscription.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}

public enum ClaudeUsageParser {
    private struct Response: Decodable {
        struct Window: Decodable { var utilization: Double?; var resetsAt: String? }
        struct Scope: Decodable { var model: Model? }
        struct Model: Decodable { var displayName: String? }
        struct Row: Decodable { var kind: String; var percent: Double?; var resetsAt: String?; var scope: Scope? }
        struct Breakdown: Decodable { var rows: [Share] }
        struct Share: Decodable { var displayName: String; var percent: Double }

        var fiveHour: Window?
        var sevenDay: Window?
        var limits: [Row]?
        var sevenDayBreakdown: Breakdown?
    }

    public struct Profile: Sendable, Equatable {
        public var plan: String?
        public var subscriptionStart: Date?
    }

    /// Plan ("Ultra plan" → "Ultra") and subscription start from the profile endpoint.
    public static func profile(_ data: Data) -> Profile? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let org = root["organization"] as? [String: Any] else { return nil }
        let plan = (org["plan_display_label"] as? String).flatMap { label -> String? in
            let trimmed = label.replacingOccurrences(of: #"\s+plan$"#, with: "", options: [.regularExpression, .caseInsensitive])
            return trimmed.isEmpty ? nil : trimmed
        }
        return Profile(plan: plan, subscriptionStart: DateParsing.iso(org["subscription_created_at"] as? String))
    }

    /// Next monthly renewal on the subscription start's day of month (the last day in shorter months).
    public static func nextRenewal(start: Date, after now: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.component(.day, from: start)
        var month = calendar.dateComponents([.year, .month], from: now)
        for _ in 0..<3 {
            guard let first = calendar.date(from: month),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
            var c = month
            c.day = min(day, days)
            if let candidate = calendar.date(from: c), candidate > now { return candidate }
            month.month = (month.month ?? 1) + 1
        }
        return nil
    }

    public static func parse(_ data: Data, plan: String?, now: Date) throws -> ProviderUsage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let r = try? decoder.decode(Response.self, from: data) else { throw UsageError.badResponse(.claude) }

        var limits: [Limit] = []
        if let w = r.fiveHour, let used = w.utilization {
            limits.append(Limit(id: "session", title: "Session (5 h)", usedPercent: used,
                                resetsAt: DateParsing.iso(w.resetsAt), windowSeconds: 5 * 3600))
        }
        if let w = r.sevenDay, let used = w.utilization {
            limits.append(Limit(id: Limit.weeklyID, title: "Week, all models", usedPercent: used,
                                resetsAt: DateParsing.iso(w.resetsAt), windowSeconds: 7 * 86400))
        }
        for row in r.limits ?? [] where row.kind == "weekly_scoped" {
            guard let used = row.percent, let name = row.scope?.model?.displayName else { continue }
            limits.append(Limit(id: "weekly-\(name.lowercased())", title: "Week, \(name)", usedPercent: used,
                                resetsAt: DateParsing.iso(row.resetsAt), windowSeconds: 7 * 86400))
        }
        guard !limits.isEmpty else { throw UsageError.badResponse(.claude) }

        let shares = (r.sevenDayBreakdown?.rows ?? []).map { Share(name: $0.displayName, percent: $0.percent) }
        return ProviderUsage(provider: .claude, plan: plan, limits: limits, breakdown: shares, fetchedAt: now)
    }
}

public struct ClaudeClient: Sendable {
    public init() {}

    public func fetch(now: Date = Date()) async throws -> ProviderUsage {
        guard let raw = try? await Shell.run("/usr/bin/security",
                                             ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let creds = ClaudeCredentials.parse(Data(raw.utf8)) else {
            throw UsageError.notLoggedIn(.claude)
        }
        if let expires = creds.expiresAt, expires < now { throw UsageError.loginExpired(.claude) }

        async let profile = try? get("https://api.anthropic.com/api/oauth/profile", token: creds.accessToken)
        let data = try await get("https://api.anthropic.com/api/oauth/usage", token: creds.accessToken)
        // The plan in the Keychain token is set at login and goes stale after an upgrade; the profile is current.
        let info = (await profile).flatMap(ClaudeUsageParser.profile)
        var usage = try ClaudeUsageParser.parse(data, plan: info?.plan ?? creds.plan, now: now)
        if let start = info?.subscriptionStart {
            usage.renewsAt = ClaudeUsageParser.nextRenewal(start: start, after: now)
            usage.renewalEstimated = true
        }
        return usage
    }

    private func get(_ url: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UsageError.http(.claude, code) }
        return data
    }
}
