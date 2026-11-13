import AILimitsCore
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderStatus()
    @Published var codex = ProviderStatus()
    @Published var now = Date()

    func start() {
        let now = Date()
        claude = ProviderStatus(usage: ProviderUsage(
            provider: .claude, plan: "Max 5x",
            limits: [Limit(id: Limit.weeklyID, title: "Week, all models", usedPercent: 38,
                           resetsAt: now.addingTimeInterval(2.6 * 86400), windowSeconds: 7 * 86400)],
            fetchedAt: now))
        codex = ProviderStatus(usage: ProviderUsage(
            provider: .codex, plan: "Plus",
            limits: [Limit(id: Limit.weeklyID, title: "Week", usedPercent: 13,
                           resetsAt: now.addingTimeInterval(4.8 * 86400), windowSeconds: 7 * 86400)],
            fetchedAt: now))
    }

    func status(_ provider: Provider) -> ProviderStatus {
        provider == .claude ? claude : codex
    }
}
