import Foundation

public enum CodexUsageParser {
    private struct Response: Decodable {
        struct Window: Decodable { var usedPercent: Double; var limitWindowSeconds: Double; var resetAt: Double? }
        struct RateLimit: Decodable { var primaryWindow: Window?; var secondaryWindow: Window? }
        var planType: String?
        var rateLimit: RateLimit?
    }

    /// Parses the ChatGPT usage endpoint answer.
    public static func parse(_ data: Data, now: Date) throws -> ProviderUsage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let r = try? decoder.decode(Response.self, from: data) else { throw UsageError.badResponse(.codex) }
        let windows = [r.rateLimit?.primaryWindow, r.rateLimit?.secondaryWindow].compactMap { $0 }.map {
            limit(used: $0.usedPercent, windowSeconds: $0.limitWindowSeconds,
                  resetsAt: $0.resetAt.map { Date(timeIntervalSince1970: $0) })
        }
        guard !windows.isEmpty else { throw UsageError.badResponse(.codex) }
        return ProviderUsage(provider: .codex, plan: r.planType.map(capitalized), limits: windows, fetchedAt: now)
    }

    /// Next renewal from the ChatGPT subscriptions endpoint; nil when the plan will not renew.
    public static func renewal(_ data: Data) -> Date? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["will_renew"] as? Bool ?? true else { return nil }
        let entitlement = root["entitlement"] as? [String: Any]
        return DateParsing.iso(entitlement?["renews_at"] as? String) ?? DateParsing.iso(root["active_until"] as? String)
    }

    /// Parses the newest `rate_limits` object of a Codex session log line.
    public static func parseLogLine(_ line: String, now: Date) -> ProviderUsage? {
        guard line.contains("\"rate_limits\""),
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let rl = payload["rate_limits"] as? [String: Any] else { return nil }
        let windows: [Limit] = ["primary", "secondary"].compactMap { key in
            guard let w = rl[key] as? [String: Any], let used = w["used_percent"] as? Double,
                  let minutes = w["window_minutes"] as? Double else { return nil }
            let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            if let reset, reset < now {
                return limit(used: 0, windowSeconds: minutes * 60, resetsAt: nil)
            }
            return limit(used: used, windowSeconds: minutes * 60, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        let at = DateParsing.iso(obj["timestamp"] as? String) ?? now
        return ProviderUsage(provider: .codex, plan: (rl["plan_type"] as? String).map(capitalized),
                             limits: windows, fetchedAt: at)
    }

    static func limit(used: Double, windowSeconds: Double, resetsAt: Date?) -> Limit {
        if windowSeconds >= 6 * 86400 {
            return Limit(id: Limit.weeklyID, title: "Week", usedPercent: used, resetsAt: resetsAt,
                         windowSeconds: windowSeconds)
        }
        let hours = Int((windowSeconds / 3600).rounded())
        return Limit(id: "session", title: "Session (\(hours) h)", usedPercent: used, resetsAt: resetsAt,
                     windowSeconds: windowSeconds)
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

public struct CodexClient: Sendable {
    let home: URL

    public init(home: URL = CodexClient.defaultHome) { self.home = home }

    public static var defaultHome: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Live numbers from the ChatGPT usage endpoint; the newest session log when that fails.
    public func fetch(now: Date = Date()) async throws -> ProviderUsage {
        do {
            return try await fetchLive(now: now)
        } catch {
            if let fromLog = newestFromLogs(now: now) { return fromLog }
            throw error
        }
    }

    func fetchLive(now: Date) async throws -> ProviderUsage {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else { throw UsageError.notLoggedIn(.codex) }

        let account = tokens["account_id"] as? String
        async let subscription = try? get("https://chatgpt.com/backend-api/subscriptions?account_id=\(account ?? "")",
                                          token: token, account: account)
        var usage = try CodexUsageParser.parse(
            try await get("https://chatgpt.com/backend-api/wham/usage", token: token, account: account), now: now)
        usage.renewsAt = (await subscription).flatMap(CodexUsageParser.renewal)
        return usage
    }

    private func get(_ url: String, token: String, account: String?) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let (body, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UsageError.http(.codex, code) }
        return body
    }

    func newestFromLogs(now: Date) -> ProviderUsage? {
        for file in CodexLogs(home: home).files(since: now.addingTimeInterval(-14 * 86400)).reversed() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() {
                if let usage = CodexUsageParser.parseLogLine(String(line), now: now) { return usage }
            }
        }
        return nil
    }
}

/// Codex session logs: ~/.codex/sessions/YYYY/MM/DD/*.jsonl.
public struct CodexLogs: Sendable {
    let home: URL

    public init(home: URL = CodexClient.defaultHome) { self.home = home }

    /// Log files changed since `date`, oldest first.
    public func files(since date: Date) -> [URL] {
        let root = home.appendingPathComponent("sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        var found: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified >= date { found.append((url, modified)) }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
