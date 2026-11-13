import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex

    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude" : "Codex" }
}

public struct Limit: Codable, Sendable, Hashable, Identifiable {
    public static let weeklyID = "weekly"

    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var windowSeconds: TimeInterval

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, windowSeconds: TimeInterval) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
    }

    public var leftPercent: Double { max(0, 100 - usedPercent) }
}

public struct Share: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var percent: Double
    public var id: String { name }

    public init(name: String, percent: Double) {
        self.name = name
        self.percent = percent
    }
}

public struct ProviderUsage: Codable, Sendable {
    public var provider: Provider
    public var plan: String?
    public var limits: [Limit]
    public var breakdown: [Share]
    public var fetchedAt: Date
    /// Next subscription renewal, when the server reports it.
    public var renewsAt: Date?
    /// True when `renewsAt` is a guess from the subscription start (Claude reports no renewal date).
    /// Optional so history files saved before this field still decode.
    public var renewalEstimated: Bool?

    public init(provider: Provider, plan: String?, limits: [Limit], breakdown: [Share] = [], fetchedAt: Date,
                renewsAt: Date? = nil) {
        self.provider = provider
        self.plan = plan
        self.limits = limits
        self.breakdown = breakdown
        self.fetchedAt = fetchedAt
        self.renewsAt = renewsAt
    }

    public var weekly: Limit? { limits.first { $0.id == Limit.weeklyID } }
}

public struct ProviderStatus: Sendable {
    public var usage: ProviderUsage?
    public var error: String?
    public var notLoggedIn: Bool

    public init(usage: ProviderUsage? = nil, error: String? = nil, notLoggedIn: Bool = false) {
        self.usage = usage
        self.error = error
        self.notLoggedIn = notLoggedIn
    }
}
