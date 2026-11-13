import Foundation
import Testing
@testable import AILimitsCore

@Suite struct ClaudeClientTests {
    let t0 = Fixed.t0

    // MARK: ClaudeUsageParser.parse

    @Test func parseMapsFiveHourSevenDayAndWeeklyScopedRowsToSessionWeeklyAndPerModelLimits() throws {
        // arrange
        let data = Factories.claudeUsageJSON(
            fiveHour: (12.5, "2027-01-15T10:00:00.123456+00:00"),
            sevenDay: (40, "2027-01-20T08:00:00Z"),
            rows: [Factories.claudeRow(kind: "weekly_scoped", percent: 30, resetsAt: "2027-01-20T08:00:00Z", model: "Opus")],
            breakdown: [("Opus", 70), ("Sonnet", 30)])

        // act
        let usage = try ClaudeUsageParser.parse(data, plan: "Max 5x", now: t0)

        // assert
        #expect(usage.limits.map(\.id) == ["session", "weekly", "weekly-opus"])
        #expect(usage.limits.map(\.windowSeconds) == [18000, 604800, 604800])
        #expect(usage.limits[0].resetsAt == Factories.iso("2027-01-15T10:00:00Z"))
        #expect(usage.weekly?.usedPercent == 40)
        #expect(usage.limits[2].title == "Week, Opus")
        #expect(usage.breakdown.map(\.name) == ["Opus", "Sonnet"])
        #expect(usage.breakdown.map(\.percent) == [70, 30])
        #expect(usage.plan == "Max 5x")
        #expect(usage.fetchedAt == t0)
    }

    @Test func parseSkipsWindowsWithNullUtilizationOtherRowKindsAndScopedRowsMissingPercentOrModelName() throws {
        // arrange
        let data = Factories.claudeUsageJSON(
            fiveHour: (nil, "2027-01-15T10:00:00Z"),
            sevenDay: (40, "2027-01-20T08:00:00Z"),
            rows: [
                Factories.claudeRow(kind: "other", percent: 50, model: "Opus"),
                Factories.claudeRow(kind: "weekly_scoped", model: "Opus"),
                Factories.claudeRow(kind: "weekly_scoped", percent: 20),
            ])

        // act
        let usage = try ClaudeUsageParser.parse(data, plan: nil, now: t0)

        // assert
        #expect(usage.limits.map(\.id) == ["weekly"])
    }

    @Test func parseKeepsALimitWithNullResetsAtAsResetsAtNil() throws {
        // arrange
        let data = Factories.claudeUsageJSON(sevenDay: (40, nil))

        // act
        let usage = try ClaudeUsageParser.parse(data, plan: nil, now: t0)

        // assert
        #expect(usage.weekly?.resetsAt == nil)
    }

    @Test(arguments: [
        Data("{}".utf8),
        Factories.claudeUsageJSON(fiveHour: (nil, nil), sevenDay: (nil, nil)),
        Data("not json".utf8),
    ])
    func parseThrowsBadResponseWhenNoLimitCanBeBuiltOrTheJSONIsMalformed(data: Data) {
        // act
        let result = Result { try ClaudeUsageParser.parse(data, plan: nil, now: Fixed.t0) }

        // assert
        #expect(throws: UsageError.badResponse(.claude)) { try result.get() }
    }

    // MARK: ClaudeCredentials

    @Test func credentialsParseReadsTheTokenTheExpiryInMillisecondsAndThePlan() throws {
        // arrange
        let data = Factories.claudeCredentialsJSON(token: "tok", expiresAtMs: 1_800_000_000_000, tier: "default_claude_max_5x")

        // act
        let credentials = try #require(ClaudeCredentials.parse(data))

        // assert
        #expect(credentials.accessToken == "tok")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(credentials.plan == "Max 5x")
    }

    @Test(arguments: [
        Factories.claudeCredentialsJSON(token: ""),
        Factories.json(["other": [:] as [String: Any]]),
        Data("not json".utf8),
    ])
    func credentialsParseReturnsNilForAnEmptyTokenMissingClaudeAiOauthOrBadJSON(data: Data) {
        // act
        let credentials = ClaudeCredentials.parse(data)

        // assert
        #expect(credentials == nil)
    }

    @Test func credentialsParseReturnsNilExpiryWhenExpiresAtIsAbsent() throws {
        // arrange
        let data = Factories.claudeCredentialsJSON(token: "tok")

        // act
        let credentials = try #require(ClaudeCredentials.parse(data))

        // assert
        #expect(credentials.expiresAt == nil)
    }

    @Test(arguments: [
        (tier: "default_claude_max_5x" as String?, subscription: nil as String?, expected: "Max 5x" as String?),
        ("default_claude_max_20x", "pro", "Max 20x"),
        ("default_claude_pro", nil, "Pro"),
        ("default_claude_ultra", nil, "Ultra"),
        ("default_claude_ai", "pro", "Pro"),
        (nil, "team", "Team"),
        (nil, nil, nil),
    ])
    func planNameFormatsTheTierSuffixAndFallsBackToTheSubscriptionType(tier: String?, subscription: String?, expected: String?) {
        // act
        let plan = ClaudeCredentials.planName(tier: tier, subscription: subscription)

        // assert
        #expect(plan == expected)
    }

    // MARK: profile

    @Test(arguments: [
        (label: "Ultra plan", expected: "Ultra" as String?),
        ("Max Plan", "Max"),
        ("Pro", "Pro"),
        (" plan", nil),
    ])
    func profileStripsATrailingPlanWordCaseInsensitivelyAndReadsTheSubscriptionStart(label: String, expected: String?) throws {
        // arrange
        let data = Factories.claudeProfileJSON(planLabel: label, subscriptionCreatedAt: "2025-03-15T09:00:00.5Z")

        // act
        let profile = try #require(ClaudeUsageParser.profile(data))

        // assert
        #expect(profile.plan == expected)
        #expect(profile.subscriptionStart == Factories.iso("2025-03-15T09:00:00Z"))
    }

    @Test func profileReturnsNilWithoutOrganization() {
        // act
        let profile = ClaudeUsageParser.profile(Data("{}".utf8))

        // assert
        #expect(profile == nil)
    }

    @Test func profileReturnsNilStartWithoutSubscriptionCreatedAt() throws {
        // arrange
        let data = Factories.claudeProfileJSON(planLabel: "Max plan")

        // act
        let profile = try #require(ClaudeUsageParser.profile(data))

        // assert
        #expect(profile.plan == "Max")
        #expect(profile.subscriptionStart == nil)
    }

    // MARK: nextRenewal

    @Test(arguments: [
        (now: "2026-11-14T23:59:59Z", expected: "2026-11-15T00:00:00Z"),
        ("2026-11-15T00:00:00Z", "2026-12-15T00:00:00Z"),
        ("2026-11-20T12:00:00Z", "2026-12-15T00:00:00Z"),
    ])
    func nextRenewalPicksTheStartsDayThisMonthOrNextMonthWhenItHasPassed(now: String, expected: String) {
        // arrange
        let start = Factories.iso("2025-03-15T09:00:00Z")

        // act
        let renewal = ClaudeUsageParser.nextRenewal(start: start, after: Factories.iso(now), calendar: Factories.utcCalendar())

        // assert
        #expect(renewal == Factories.iso(expected))
    }

    @Test(arguments: [
        (start: "2025-01-31T00:00:00Z", now: "2026-02-10T00:00:00Z", expected: "2026-02-28T00:00:00Z"),
        ("2024-02-29T00:00:00Z", "2027-02-01T00:00:00Z", "2027-02-28T00:00:00Z"),
        ("2025-03-15T00:00:00Z", "2026-12-20T00:00:00Z", "2027-01-15T00:00:00Z"),
    ])
    func nextRenewalUsesTheLastDayOfAShorterMonthAndRollsDecemberIntoJanuary(start: String, now: String, expected: String) {
        // act
        let renewal = ClaudeUsageParser.nextRenewal(start: Factories.iso(start), after: Factories.iso(now), calendar: Factories.utcCalendar())

        // assert
        #expect(renewal == Factories.iso(expected))
    }
}
