import Foundation

public struct DailyModelUsage: Sendable, Hashable, Identifiable {
    public var day: Date
    public var model: String
    public var tokens: Double
    public var cost: Double
    public var id: String { "\(day.timeIntervalSince1970)-\(model)" }

    public init(day: Date, model: String, tokens: Double, cost: Double) {
        self.day = day
        self.model = model
        self.tokens = tokens
        self.cost = cost
    }
}

public struct ProjectUsage: Sendable, Hashable, Identifiable {
    public var name: String
    public var path: String
    public var tokens: Double
    public var cost: Double
    public var id: String { path }

    public init(name: String, path: String, tokens: Double, cost: Double) {
        self.name = name
        self.path = path
        self.tokens = tokens
        self.cost = cost
    }
}

public struct TokenUsage: Sendable {
    public var daily: [DailyModelUsage]
    public var projects: [ProjectUsage]
    /// True when the cost per model is known; Codex reports cost only per day.
    public var costPerModel: Bool

    public init(daily: [DailyModelUsage], projects: [ProjectUsage], costPerModel: Bool) {
        self.daily = daily
        self.projects = projects
        self.costPerModel = costPerModel
    }

    public var totalTokens: Double { daily.reduce(0) { $0 + $1.tokens } }
    public var totalCost: Double { daily.reduce(0) { $0 + $1.cost } }
}

/// Reads token usage from the local Claude Code and Codex logs through ccusage.
public enum CCUsage {
    public static let package = "ccusage@20.0.50"

    public static func claude(days: Int = 30, now: Date = Date()) async throws -> TokenUsage {
        let json = try await run(["claude", "daily", "--json", "--breakdown", "--instances", "--since", since(days, now)])
        return try parseClaudeInstances(Data(json.utf8), resolve: ProjectPath.resolve)
    }

    public static func codex(days: Int = 30, now: Date = Date()) async throws -> TokenUsage {
        let json = try await run(["codex", "daily", "--json", "--since", since(days, now)])
        return try parseCodexDaily(Data(json.utf8))
    }

    /// Runs through a login shell so the Node that the user's shell sets up (fnm, nvm, Homebrew) is found.
    static func run(_ args: [String]) async throws -> String {
        let command = (["npx", "-y", package] + args).map { "'\($0)'" }.joined(separator: " ")
        return try await Shell.run("/bin/zsh", ["-lc", command])
    }

    static func since(_ days: Int, _ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: now.addingTimeInterval(-Double(days - 1) * 86400))
    }

    private struct ModelRow: Decodable {
        var modelName: String
        var inputTokens: Double
        var outputTokens: Double
        var cacheCreationTokens: Double
        var cacheReadTokens: Double
        var cost: Double
    }

    private struct ClaudeDay: Decodable {
        var date: String
        var modelBreakdowns: [ModelRow]
    }

    public static func parseClaudeInstances(_ data: Data, resolve: (String) -> String) throws -> TokenUsage {
        struct Root: Decodable { var projects: [String: [ClaudeDay]] }
        let root = try JSONDecoder().decode(Root.self, from: data)
        var perDay: [String: DailyModelUsage] = [:]
        var projects: [ProjectUsage] = []
        for (encoded, days) in root.projects {
            var tokens = 0.0, cost = 0.0
            for day in days {
                guard let date = dayDate(day.date) else { continue }
                for m in day.modelBreakdowns {
                    let t = m.inputTokens + m.outputTokens + m.cacheCreationTokens + m.cacheReadTokens
                    tokens += t
                    cost += m.cost
                    let model = ModelName.short(m.modelName)
                    let key = "\(day.date)|\(model)"
                    perDay[key, default: DailyModelUsage(day: date, model: model, tokens: 0, cost: 0)].tokens += t
                    perDay[key]?.cost += m.cost
                }
            }
            let path = resolve(encoded)
            projects.append(ProjectUsage(name: (path as NSString).lastPathComponent, path: path, tokens: tokens, cost: cost))
        }
        return TokenUsage(daily: perDay.values.sorted { ($0.day, $0.model) < ($1.day, $1.model) },
                          projects: projects.sorted { $0.cost > $1.cost },
                          costPerModel: true)
    }

    public static func parseCodexDaily(_ data: Data) throws -> TokenUsage {
        struct Model: Decodable { var totalTokens: Double }
        struct Day: Decodable { var date: String; var costUSD: Double?; var models: [String: Model] }
        struct Root: Decodable { var daily: [Day] }
        let root = try JSONDecoder().decode(Root.self, from: data)
        var rows: [DailyModelUsage] = []
        for day in root.daily {
            guard let date = dayDate(day.date) else { continue }
            let total = day.models.values.reduce(0) { $0 + $1.totalTokens }
            for (name, m) in day.models.sorted(by: { $0.key < $1.key }) {
                // Codex reports cost per day only; split it by token share so the day total stays right.
                let share = total > 0 ? m.totalTokens / total : 0
                rows.append(DailyModelUsage(day: date, model: ModelName.short(name), tokens: m.totalTokens,
                                            cost: (day.costUSD ?? 0) * share))
            }
        }
        return TokenUsage(daily: rows, projects: [], costPerModel: false)
    }

    static func dayDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }
}

public enum ModelName {
    /// "claude-opus-5-5" → "Opus 5.5", "claude-3-5-sonnet-20241022" → "Sonnet 3.5"; other names stay as they are.
    public static func short(_ name: String) -> String {
        guard name.hasPrefix("claude-") else { return name }
        let parts = name.dropFirst("claude-".count).split(separator: "-")
        guard let familyIndex = parts.firstIndex(where: { $0.contains(where: \.isLetter) }) else { return name }
        let family = parts[familyIndex]
        let isVersion = { (p: Substring) in p.allSatisfy(\.isNumber) && p.count <= 2 }
        let after = parts[(familyIndex + 1)...].prefix(while: isVersion)
        let before = parts[..<familyIndex].filter(isVersion)
        let version = (after.isEmpty ? Array(before) : Array(after)).joined(separator: ".")
        let title = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? title : "\(title) \(version)"
    }
}

public enum ProjectPath {
    /// Claude Code stores projects as the folder path with "/" and "." replaced by "-", so "/.name" becomes "--name".
    /// Walks the disk to find the real folder; falls back to the encoded name.
    public static func resolve(_ encoded: String) -> String {
        resolve(encoded, exists: { FileManager.default.fileExists(atPath: $0) })
    }

    public static func resolve(_ encoded: String, exists: (String) -> Bool) -> String {
        // "--name" is "/.name": an empty part marks a hidden folder.
        var parts: [String] = []
        var hidden = false
        for part in encoded.split(separator: "-", omittingEmptySubsequences: false).dropFirst() {
            if part.isEmpty { hidden = true; continue }
            parts.append(hidden ? "." + part : String(part))
            hidden = false
        }
        var path = ""
        var i = 0
        while i < parts.count {
            var matched = false
            for j in stride(from: parts.count, to: i, by: -1) {
                let name = parts[i..<j].joined(separator: "-")
                for candidate in [path + "/" + name] where exists(candidate) {
                    path = candidate
                    i = j
                    matched = true
                    break
                }
                if matched { break }
            }
            if !matched {
                return path + "/" + parts[i...].joined(separator: "-")
            }
        }
        return path.isEmpty ? encoded : path
    }
}
