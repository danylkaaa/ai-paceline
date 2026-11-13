import Foundation
import Testing
@testable import AILimitsCore

@Suite struct TokenUsageTests {
    static let opus = "claude-opus-4-1"
    static let opusDated = "claude-opus-4-1-20250805"
    static let sonnet = "claude-sonnet-4-5"
    static let haiku = "claude-haiku-4-5"
    static let day1 = "2027-01-10"
    static let day2 = "2027-01-11"

    func dayDate(_ text: String) -> Date { CCUsage.dayDate(text)! }

    /// Noon in the local time zone, so the local date holds in every zone.
    func localNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func parseClaude(_ data: Data) throws -> TokenUsage {
        try CCUsage.parseClaudeInstances(data, resolve: { $0 })
    }

    @Test func parseClaudeInstancesSumsAllFourTokenKindsAndTheCostPerProject() throws {
        // arrange
        let row = Factories.modelRow(Self.opus, input: 1, output: 2, cacheCreation: 3, cacheRead: 4, cost: 0.5)
        let data = Factories.claudeInstancesJSON(projects: ["-Users-a-proj": [Factories.claudeDay(Self.day1, [row])]])

        // act
        let usage = try CCUsage.parseClaudeInstances(data, resolve: { _ in "/Users/a/proj" })

        // assert
        #expect(usage.projects == [ProjectUsage(name: "proj", path: "/Users/a/proj", tokens: 10, cost: 0.5)])
        #expect(usage.costPerModel == true)
    }

    @Test func parseClaudeInstancesMergesTheSameDayAndShortModelNameAcrossProjectsAndModelIds() throws {
        // arrange
        let data = Factories.claudeInstancesJSON(projects: [
            "A": [Factories.claudeDay(Self.day1, [Factories.modelRow(Self.opus, input: 100, cost: 1.25)])],
            "B": [Factories.claudeDay(Self.day1, [Factories.modelRow(Self.opusDated, input: 50, cost: 0.75)])],
        ])

        // act
        let usage = try parseClaude(data)

        // assert
        #expect(usage.daily.count == 1)
        #expect(usage.daily[0].model == "Opus 4.1")
        #expect(usage.daily[0].tokens == 150)
        #expect(usage.daily[0].cost == 2.0)
        #expect(usage.totalCost == 2.0)
    }

    @Test func parseClaudeInstancesSortsDailyByDayThenModelAndProjectsByCostDescending() throws {
        // arrange
        let data = Factories.claudeInstancesJSON(projects: [
            "cheap": [Factories.claudeDay(Self.day2, [Factories.modelRow(Self.sonnet, cost: 1)]),
                      Factories.claudeDay(Self.day1, [Factories.modelRow(Self.sonnet, cost: 0),
                                                      Factories.modelRow(Self.opus, cost: 0),
                                                      Factories.modelRow(Self.haiku, cost: 0)])],
            "dear": [Factories.claudeDay(Self.day1, [Factories.modelRow(Self.opus, cost: 3)])],
        ])
        let expected = [(dayDate(Self.day1), "Haiku 4.5"), (dayDate(Self.day1), "Opus 4.1"),
                        (dayDate(Self.day1), "Sonnet 4.5"), (dayDate(Self.day2), "Sonnet 4.5")]

        // act
        let usage = try parseClaude(data)

        // assert
        let order = usage.daily.map { ($0.day, $0.model) }
        #expect(order.count == expected.count)
        #expect(zip(order, expected).allSatisfy { $0 == $1 })
        #expect(usage.projects.map(\.cost) == [3, 1])
    }

    @Test func parseClaudeInstancesSkipsADayWithAnUnparseableDateIncludingFromProjectTotals() throws {
        // arrange
        let data = Factories.claudeInstancesJSON(projects: ["p": [
            Factories.claudeDay(Self.day1, [Factories.modelRow(Self.opus, cost: 1)]),
            Factories.claudeDay("bad-date", [Factories.modelRow(Self.opus, cost: 5)]),
        ]])

        // act
        let usage = try parseClaude(data)

        // assert
        #expect(usage.daily.count == 1)
        #expect(usage.projects[0].cost == 1)
    }

    @Test(arguments: ["not json", "{}"])
    func parseClaudeInstancesThrowsOnMalformedJSON(text: String) {
        // arrange
        let data = Data(text.utf8)

        // act
        let result = Result { try CCUsage.parseClaudeInstances(data, resolve: { $0 }) }

        // assert
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test func parseCodexDailySplitsTheDayCostByTokenShareSoModelCostsSumToTheDayCost() throws {
        // arrange
        let data = Factories.codexDailyJSON(days: [(Self.day1, 3.0, ["gpt-5": 300, "gpt-5-codex": 100])])

        // act
        let usage = try CCUsage.parseCodexDaily(data)

        // assert
        let rows = usage.daily.sorted { $0.model < $1.model }
        #expect(rows.map(\.model) == ["gpt-5", "gpt-5-codex"])
        #expect(rows.map(\.cost) == [2.25, 0.75])
        #expect(abs(usage.totalCost - 3.0) < 1e-9)
        #expect(usage.costPerModel == false)
        #expect(usage.projects.isEmpty)
    }

    @Test(arguments: [(1.0 as Double?, 0.0), (nil, 100.0)])
    func parseCodexDailyGivesZeroCostNotNaNForADayWithZeroTokensOrNoCostUSD(costUSD: Double?, tokens: Double) throws {
        // arrange
        let data = Factories.codexDailyJSON(days: [(Self.day1, costUSD, ["gpt-5": tokens])])

        // act
        let usage = try CCUsage.parseCodexDaily(data)

        // assert
        #expect(usage.daily[0].cost == 0)
        #expect(!usage.daily[0].cost.isNaN)
        #expect(usage.totalCost == 0)
    }

    @Test func parseCodexDailySkipsADayWithAnUnparseableDate() throws {
        // arrange
        let data = Factories.codexDailyJSON(days: [("bad", 9, ["gpt-5": 10]), (Self.day1, 1, ["gpt-5": 10])])

        // act
        let usage = try CCUsage.parseCodexDaily(data)

        // assert
        #expect(usage.totalCost == 1)
        #expect(usage.daily.allSatisfy { $0.day == CCUsage.dayDate(Self.day1) })
    }

    @Test(arguments: [(30, 2027, 1, 30, "20270101"), (1, 2027, 1, 30, "20270130"),
                      (30, 2027, 3, 1, "20270131"), (30, 2027, 1, 15, "20261217")])
    func sinceGivesTheFirstDayOfAWindowOfNDaysTodayIncluded(days: Int, year: Int, month: Int, day: Int, expected: String) {
        // arrange
        let now = localNoon(year, month, day)

        // act
        let result = CCUsage.since(days, now)

        // assert
        #expect(result == expected)
    }

    @Test(arguments: [
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-sonnet-4-5-20250929", "Sonnet 4.5"),
        ("claude-opus-4", "Opus 4"),
        ("claude-haiku", "Haiku"),
        ("claude-opus-4-20250514", "Opus 4"),
        ("gpt-5-codex", "gpt-5-codex"),
    ])
    func modelNameShortShortensClaudeIdsAndLeavesOtherNamesUnchanged(name: String, expected: String) {
        // act
        let result = ModelName.short(name)

        // assert
        #expect(result == expected)
    }

    @Test func projectPathResolveRebuildsAFolderWhoseNameContainsADashPreferringTheLongestExistingName() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo", "/Users/demo/Developer",
                                     "/Users/demo/Developer/ai", "/Users/demo/Developer/ai-limits"]

        // act
        let path = ProjectPath.resolve("-Users-demo-Developer-ai-limits", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/Developer/ai-limits")
    }

    @Test func projectPathResolveKeepsTheUnresolvedTailAsOneDashedNameWhenAFolderIsGone() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo"]

        // act
        let path = ProjectPath.resolve("-Users-demo-gone-project", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/gone-project")
    }

    @Test func projectPathResolveFindsAHiddenFolderEncodedAsADoubleDash() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo", "/Users/demo/.claude"]

        // act
        let path = ProjectPath.resolve("-Users-demo--claude", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/.claude")
    }

    @Test(arguments: [
        ("claude-3-5-sonnet-20241022", "Sonnet 3.5"),
        ("claude-3-7-sonnet-20250219", "Sonnet 3.7"),
        ("claude-3-opus-20240229", "Opus 3"),
        ("claude-3-5-haiku-latest", "Haiku 3.5"),
        ("claude-3-5", "claude-3-5"),
    ])
    func modelNameShortensLegacyClaudeIds(id: String, expected: String) {
        // act
        let result = ModelName.short(id)

        // assert
        #expect(result == expected)
    }

    @Test(arguments: [
        ("-Users-demo--claude", "/Users/demo/.claude"),
        ("-Users-demo-claude", "/Users/demo/claude"),
    ])
    func projectPathResolvePicksTheHiddenFolderForADoubleDashAndTheVisibleOneForASingleDashWhenBothExist(encoded: String, expected: String) {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo", "/Users/demo/claude", "/Users/demo/.claude"]

        // act
        let path = ProjectPath.resolve(encoded, exists: { existing.contains($0) })

        // assert
        #expect(path == expected)
    }

    @Test func projectPathResolveKeepsTheDotOnAHiddenFolderThatIsGone() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo"]

        // act
        let path = ProjectPath.resolve("-Users-demo--gone", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/.gone")
    }

    @Test func projectPathResolveAppliesTheHiddenMarkOnlyToTheNextPart() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo", "/Users/demo/.config", "/Users/demo/.config/app"]

        // act
        let path = ProjectPath.resolve("-Users-demo--config-app", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/.config/app")
    }

    @Test func projectPathResolveKeepsAGoneVisibleFolderWhenAHiddenOneHasTheSameName() {
        // arrange
        let existing: Set<String> = ["/Users", "/Users/demo", "/Users/demo/.claude"]

        // act
        let path = ProjectPath.resolve("-Users-demo-claude", exists: { existing.contains($0) })

        // assert
        #expect(path == "/Users/demo/claude")
    }
}
