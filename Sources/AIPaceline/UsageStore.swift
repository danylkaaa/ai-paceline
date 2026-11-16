import AIPacelineCore
import Foundation
import os

let log = Logger(subsystem: "io.github.danylkaaa.aipaceline", category: "usage")

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderStatus()
    @Published var codex = ProviderStatus()
    @Published var now = Date()
    @Published var refreshing = false
    private var refreshingTokens = false
    @Published var lastRefresh: Date?
    @Published var tokens: [Provider: TokenUsage] = [:]
    @Published var tokenErrors: [Provider: String] = [:]
    @Published var history: History

    private let claudeClient = ClaudeClient()
    private let codexClient = CodexClient()
    private var ticker: Timer?
    private let historyFile = HistoryFile()

    init() {
        if Launch.demo {
            let now = Date()
            history = DemoData.history(now: now)
            claude = ProviderStatus(usage: DemoData.claude(now: now))
            codex = ProviderStatus(usage: DemoData.codex(now: now))
            tokens = [.claude: DemoData.tokens(.claude, now: now), .codex: DemoData.tokens(.codex, now: now)]
            lastRefresh = now
            return
        }
        history = historyFile.load()
        claude = ProviderStatus(usage: history.last[.claude])
        codex = ProviderStatus(usage: history.last[.codex])
    }

    func start() {
        guard !Launch.demo else { return }
        Task { await backfillCodexHistory() }
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
        let minutes = Double(AppDefaults.store.integer(forKey: Settings.refreshMinutes))
        guard let last = lastRefresh, !refreshing else { return }
        if now.timeIntervalSince(last) >= max(1, minutes) * 60 - 5 || resetPassed(since: last) {
            Task { await refresh() }
        }
    }

    /// A shown limit reached its reset time after the last refresh, so its numbers are old.
    private func resetPassed(since last: Date) -> Bool {
        [claude, codex].compactMap(\.usage).flatMap(\.limits).contains { limit in
            guard let reset = limit.resetsAt else { return false }
            return reset <= now && reset > last
        }
    }

    func refresh(waitForTokens: Bool = false) async {
        if Launch.demo { now = Date(); lastRefresh = now; return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        async let c = Self.load(.claude) { try await self.claudeClient.fetch() }
        async let x = Self.load(.codex) { try await self.codexClient.fetch() }
        let (claudeResult, codexResult) = await (c, x)
        claude = Self.merge(claude, claudeResult)
        codex = Self.merge(codex, codexResult)
        for case .success(let usage) in [claudeResult, codexResult] { history.record(usage) }
        saveHistory()
        now = Date()
        lastRefresh = now
        if waitForTokens { await refreshTokens() } else { Task { await refreshTokens() } }
    }

    private func saveHistory() {
        do {
            try historyFile.save(history)
        } catch {
            log.error("history save failed error=\(String(describing: error), privacy: .public)")
        }
    }

    /// Codex logs every turn's limits, so its weekly history can be filled from them at start.
    func backfillCodexHistory() async {
        guard !Launch.demo else { return }
        let since = Date().addingTimeInterval(-History.keepDays * 86400)
        let points = await Task.detached { CodexHistory.points(from: CodexLogs(), since: since) }.value
        for point in points { history.add(point) }
        saveHistory()
    }

    /// Runs apart from `refresh`: ccusage can take minutes, and the limits must not wait for it.
    private func refreshTokens() async {
        guard !refreshingTokens else { return }
        refreshingTokens = true
        defer { refreshingTokens = false }
        async let c = Self.loadTokens(.claude) { try await CCUsage.claude(days: 60) }
        async let x = Self.loadTokens(.codex) { try await CCUsage.codex(days: 60) }
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
