import Foundation

public struct HistoryPoint: Codable, Sendable, Hashable {
    public var provider: Provider
    public var at: Date
    public var usedPercent: Double
    public var resetsAt: Date

    public init(provider: Provider, at: Date, usedPercent: Double, resetsAt: Date) {
        self.provider = provider
        self.at = at
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// One weekly window: points from its start (0%) to the last saved value.
public struct UsageWindow: Sendable, Identifiable {
    public var start: Date
    public var resetsAt: Date
    public var points: [HistoryPoint]
    public var id: Date { resetsAt }
}

/// Saved state: the weekly % over time and the last good numbers per provider.
public struct History: Codable, Sendable {
    public static let keepDays = 60.0

    public var points: [HistoryPoint] = []
    public var last: [Provider: ProviderUsage] = [:]

    public init() {}

    public mutating func record(_ usage: ProviderUsage) {
        last[usage.provider] = usage
        guard let weekly = usage.weekly, let reset = weekly.resetsAt else { return }
        add(HistoryPoint(provider: usage.provider, at: usage.fetchedAt, usedPercent: weekly.usedPercent, resetsAt: reset))
    }

    /// Adds a point unless the provider already has one at the same time; keeps points sorted and pruned.
    public mutating func add(_ point: HistoryPoint) {
        guard !points.contains(where: { $0.provider == point.provider && abs($0.at.timeIntervalSince(point.at)) < 1 }) else {
            return
        }
        points.append(point)
        points.sort { $0.at < $1.at }
        let cutoff = point.at.addingTimeInterval(-Self.keepDays * 86400)
        points.removeAll { $0.at < cutoff }
    }

    /// Weekly windows of a provider, oldest first. Servers jitter reset times by seconds, so resets less than
    /// an hour apart belong to one window.
    public func windows(_ provider: Provider, windowSeconds: TimeInterval = 7 * 86400) -> [UsageWindow] {
        var groups: [[HistoryPoint]] = []
        for p in points.filter({ $0.provider == provider }).sorted(by: { $0.resetsAt < $1.resetsAt }) {
            if let last = groups.last?.last, p.resetsAt.timeIntervalSince(last.resetsAt) < 3600 {
                groups[groups.count - 1].append(p)
            } else {
                groups.append([p])
            }
        }
        return groups.compactMap { pts in
            guard let reset = pts.map(\.resetsAt).max() else { return nil }
            return UsageWindow(start: reset.addingTimeInterval(-windowSeconds), resetsAt: reset,
                               points: pts.sorted { $0.at < $1.at })
        }
    }
}

public struct HistoryFile: Sendable {
    public let url: URL

    public init(url: URL = HistoryFile.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AILimits/history.json")
    }

    /// Loads the saved history. A file that does not decode is moved to `history.json.bak`, so a format change
    /// never silently overwrites old data.
    public func load() -> History {
        guard let data = try? Data(contentsOf: url) else { return History() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let history = try? decoder.decode(History.self, from: data) { return history }
        let backup = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return History()
    }

    public func save(_ history: History) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(history).write(to: url, options: .atomic)
    }
}

public enum CodexHistory {
    /// Weekly % points from Codex session logs (every model turn logs the current limits).
    public static func points(from logs: CodexLogs, since: Date) -> [HistoryPoint] {
        var result: [HistoryPoint] = []
        for file in logs.files(since: since) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"rate_limits\"") {
                if let p = point(fromLogLine: String(line)), p.at >= since { result.append(p) }
            }
        }
        return result
    }

    public static func point(fromLogLine line: String) -> HistoryPoint? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let at = DateParsing.iso(obj["timestamp"] as? String),
              let payload = obj["payload"] as? [String: Any],
              let rl = payload["rate_limits"] as? [String: Any] else { return nil }
        for key in ["secondary", "primary"] {
            guard let w = rl[key] as? [String: Any], let minutes = w["window_minutes"] as? Double, minutes >= 6 * 1440,
                  let used = w["used_percent"] as? Double, let reset = w["resets_at"] as? Double else { continue }
            return HistoryPoint(provider: .codex, at: at, usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
        }
        return nil
    }
}
