import Foundation
import Testing
@testable import AIPacelineCore

@Suite struct CodexClientTests {
    let t0 = Fixed.t0

    // MARK: parse

    @Test func parseMapsPrimaryToASessionLimitAndSecondaryToTheWeeklyLimitWithThePlanCapitalized() throws {
        // arrange
        let data = Factories.codexUsageJSON(
            plan: "plus",
            primary: Factories.codexUsageWindow(used: 20, seconds: 18000, resetAt: Fixed.reset1),
            secondary: Factories.codexUsageWindow(used: 55, seconds: 604800, resetAt: Fixed.reset2))

        // act
        let usage = try CodexUsageParser.parse(data, now: t0)

        // assert
        #expect(usage.plan == "Plus")
        #expect(usage.limits.map(\.id) == ["session", "weekly"])
        #expect(usage.limits.map(\.title) == ["Session (5 h)", "Week"])
        #expect(usage.limits.map(\.resetsAt) == [Date(timeIntervalSince1970: Fixed.reset1), Date(timeIntervalSince1970: Fixed.reset2)])
        #expect(usage.fetchedAt == t0)
    }

    @Test func parseKeepsAWindowWithNoResetAtAsResetsAtNilAndPlanNilWhenPlanTypeIsMissing() throws {
        // arrange
        let data = Factories.codexUsageJSON(secondary: Factories.codexUsageWindow(used: 55, seconds: 604800))

        // act
        let usage = try CodexUsageParser.parse(data, now: t0)

        // assert
        #expect(usage.limits.count == 1)
        #expect(usage.weekly?.resetsAt == nil)
        #expect(usage.plan == nil)
    }

    @Test(arguments: [
        Data(#"{"plan_type": "plus"}"#.utf8),
        Data(#"{"rate_limit": {}}"#.utf8),
        Data("not json".utf8),
    ])
    func parseThrowsBadResponseWithoutWindowsOrOnMalformedJSON(data: Data) {
        // act
        let result = Result { try CodexUsageParser.parse(data, now: Fixed.t0) }

        // assert
        #expect(throws: UsageError.badResponse(.codex)) { try result.get() }
    }

    // MARK: limit

    @Test(arguments: [
        (seconds: 6.0 * 86400, id: "weekly", title: "Week"),
        (6.0 * 86400 - 1, "session", "Session (144 h)"),
        (18000.0, "session", "Session (5 h)"),
    ])
    func limitTreatsAWindowOfExactlySixDaysAsWeeklyAndOneSecondShorterAsASession(seconds: Double, id: String, title: String) {
        // act
        let limit = CodexUsageParser.limit(used: 10, windowSeconds: seconds, resetsAt: nil)

        // assert
        #expect(limit.id == id)
        #expect(limit.title == title)
    }

    // MARK: renewal

    @Test(arguments: [
        (json: #"{"will_renew": true, "entitlement": {"renews_at": "\#(Fixed.renewsAt)"}, "active_until": "\#(Fixed.activeUntil)"}"#,
         expected: Fixed.renewsAt),
        (#"{"entitlement": {}, "active_until": "\#(Fixed.activeUntil)"}"#, Fixed.activeUntil),
        (#"{"entitlement": {"renews_at": "\#(Fixed.renewsAt)"}}"#, Fixed.renewsAt),
    ])
    func renewalPrefersEntitlementRenewsAtFallsBackToActiveUntilAndTreatsAMissingWillRenewAsRenewing(json: String, expected: String) {
        // act
        let renewal = CodexUsageParser.renewal(Data(json.utf8))

        // assert
        #expect(renewal == Factories.iso(expected))
    }

    @Test(arguments: [
        Data(#"{"will_renew": false, "entitlement": {"renews_at": "\#(Fixed.renewsAt)"}}"#.utf8),
        Data("not json".utf8),
    ])
    func renewalReturnsNilWhenThePlanWillNotRenewOrTheJSONIsMalformed(data: Data) {
        // act
        let renewal = CodexUsageParser.renewal(data)

        // assert
        #expect(renewal == nil)
    }

    // MARK: parseLogLine

    @Test func parseLogLineReadsBothWindowsAndTheTimestampOfASessionLogLine() throws {
        // arrange
        let now = t0 + 3600
        let line = Factories.codexLogLine(
            timestamp: "2027-01-15T08:00:00.5Z",
            planType: "pro",
            primary: Factories.codexLogWindow(minutes: 300, used: 10, resetsAt: now.timeIntervalSince1970 + 1000),
            secondary: Factories.codexLogWindow(minutes: 10080, used: 55, resetsAt: now.timeIntervalSince1970 + 2000))

        // act
        let usage = try #require(CodexUsageParser.parseLogLine(line, now: now))

        // assert
        #expect(usage.limits.map(\.id) == ["session", "weekly"])
        #expect(usage.limits.map(\.usedPercent) == [10, 55])
        #expect(usage.limits.map(\.windowSeconds) == [18000, 604800])
        #expect(usage.fetchedAt == Factories.iso("2027-01-15T08:00:00Z"))
        #expect(usage.plan == "Pro")
    }

    @Test func parseLogLineResetsAWindowWhoseResetsAtHasPassedToZeroPercentWithNoResetTime() throws {
        // arrange
        let line = Factories.codexLogLine(
            timestamp: "2027-01-15T07:00:00Z",
            primary: Factories.codexLogWindow(minutes: 300, used: 10, resetsAt: t0.timeIntervalSince1970),
            secondary: Factories.codexLogWindow(minutes: 10080, used: 55, resetsAt: t0.timeIntervalSince1970 - 1))

        // act
        let usage = try #require(CodexUsageParser.parseLogLine(line, now: t0))

        // assert
        #expect(usage.weekly?.usedPercent == 0)
        #expect(usage.weekly?.resetsAt == nil)
        #expect(usage.limits[0].usedPercent == 10)
        #expect(usage.limits[0].resetsAt == t0)
    }

    @Test func parseLogLineUsesNowAsFetchedAtWhenTheLineHasNoTimestamp() throws {
        // arrange
        let line = Factories.codexLogLine(primary: Factories.codexLogWindow(minutes: 300, used: 10, resetsAt: t0.timeIntervalSince1970 + 100))

        // act
        let usage = try #require(CodexUsageParser.parseLogLine(line, now: t0))

        // assert
        #expect(usage.fetchedAt == t0)
    }

    @Test(arguments: [
        #"{"payload":{"other":1}}"#,
        Factories.codexLogLine(primary: Factories.codexLogWindow(minutes: 300, resetsAt: Fixed.reset1)),
        Factories.codexLogLine(primary: Factories.codexLogWindow(used: 10, resetsAt: Fixed.reset1)),
        #"not json "rate_limits""#,
    ])
    func parseLogLineReturnsNilWithoutRateLimitsOrUsableWindows(line: String) {
        // act
        let usage = CodexUsageParser.parseLogLine(line, now: Fixed.t0)

        // assert
        #expect(usage == nil)
    }
}
