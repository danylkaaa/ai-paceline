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

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 20)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UsageError.http(.claude, code) }
        return try ClaudeUsageParser.parse(data, plan: creds.plan, now: now)
    }
}
