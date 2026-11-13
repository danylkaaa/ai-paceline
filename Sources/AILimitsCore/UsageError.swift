import Foundation

public enum UsageError: LocalizedError, Equatable {
    case notLoggedIn(Provider)
    case loginExpired(Provider)
    case http(Provider, Int)
    case badResponse(Provider)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn(let p):
            return p == .claude ? "Not logged in to Claude Code." : "Not logged in to Codex."
        case .loginExpired(let p):
            return p == .claude
                ? "Claude login expired. Open Claude Code to refresh it."
                : "Codex login expired. Open Codex to refresh it."
        case .http(let p, let code):
            return code == 401 || code == 403
                ? "\(p.name) refused the login (\(code)). Open \(p == .claude ? "Claude Code" : "Codex") to refresh it."
                : "\(p.name) usage server answered \(code)."
        case .badResponse(let p):
            return "\(p.name) usage server sent data this app cannot read."
        }
    }
}

enum DateParsing {
    /// Parses ISO 8601 with or without fractional seconds of any length.
    static func iso(_ text: String?) -> Date? {
        guard let text else { return nil }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
