import AILimitsCore
import Foundation
import os

let log = Logger(subsystem: "local.ailimits", category: "usage")

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderStatus()
    @Published var codex = ProviderStatus()
    @Published var now = Date()
    @Published var refreshing = false
    @Published var lastRefresh: Date?
    @Published var tokens: [Provider: TokenUsage] = [:]
    @Published var tokenErrors: [Provider: String] = [:]

    private let claudeClient = ClaudeClient()
    private let codexClient = CodexClient()
    private var ticker: Timer?

    func start() {
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Task { await refresh() }
    }

    func status(_ provider: Provider) -> ProviderStatus {
        provider == .claude ? claude : codex
    }

    private func tick() {
        now = Date()
        if let last = lastRefresh, now.timeIntervalSince(last) >= 15 * 60, !refreshing {
            Task { await refresh() }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        async let c = Self.load(.claude) { try await self.claudeClient.fetch() }
        async let x = Self.load(.codex) { try await self.codexClient.fetch() }
        let (claudeResult, codexResult) = await (c, x)
        claude = Self.merge(claude, claudeResult)
        codex = Self.merge(codex, codexResult)
        now = Date()
        lastRefresh = now
        await refreshTokens()
    }

    private func refreshTokens() async {
        async let c = Self.loadTokens(.claude) { try await CCUsage.claude() }
        async let x = Self.loadTokens(.codex) { try await CCUsage.codex() }
        for (provider, result) in await [(Provider.claude, c), (.codex, x)] {
            switch result {
            case .success(let usage):
                tokens[provider] = usage
                tokenErrors[provider] = nil
            case .failure(let error):
                tokenErrors[provider] = "Token history not available: \(error)"
            }
        }
    }

    private static func loadTokens(_ provider: Provider,
                                   _ load: @Sendable () async throws -> TokenUsage) async -> Result<TokenUsage, Error> {
        do {
            return .success(try await load())
        } catch {
            log.error("ccusage failed provider=\(provider.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }

    private static func load(_ provider: Provider,
                             _ fetch: @Sendable () async throws -> ProviderUsage) async -> Result<ProviderUsage, Error> {
        do {
            return .success(try await fetch())
        } catch {
            log.error("usage fetch failed provider=\(provider.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }

    /// Keeps the last good numbers when a fetch fails.
    private static func merge(_ old: ProviderStatus, _ result: Result<ProviderUsage, Error>) -> ProviderStatus {
        switch result {
        case .success(let usage): return ProviderStatus(usage: usage)
        case .failure(let error):
            if case .notLoggedIn = error as? UsageError { return ProviderStatus(notLoggedIn: true) }
            return ProviderStatus(usage: old.usage, error: error.localizedDescription)
        }
    }
}
