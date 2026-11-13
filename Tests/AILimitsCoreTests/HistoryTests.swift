import Foundation
import Testing
@testable import AILimitsCore

@Suite struct HistoryTests {
    let t0 = Fixed.t0
    let day: TimeInterval = 86400

    // MARK: record

    @Test func recordStoresTheLastUsageAndAddsAPointFromTheWeeklyLimit() {
        // arrange
        var history = History()
        let usage = Factories.usage(.claude, fetchedAt: t0, limits: [
            Factories.namedLimit(id: "session"),
            Factories.namedLimit(id: Limit.weeklyID, usedPercent: 42, resetsAt: t0 + day),
        ])

        // act
        history.record(usage)

        // assert
        #expect(history.last[.claude]?.fetchedAt == t0)
        #expect(history.points == [HistoryPoint(provider: .claude, at: t0, usedPercent: 42, resetsAt: t0 + day)])
    }

    @Test(arguments: [
        Factories.usage(limits: [Factories.namedLimit(id: "session", resetsAt: Fixed.t0 + 100)]),
        Factories.usage(limits: [Factories.namedLimit(id: Limit.weeklyID, resetsAt: nil)]),
    ])
    func recordKeepsTheLastUsageButAddsNoPointWhenWeeklyIsMissingOrHasNoReset(usage: ProviderUsage) {
        // arrange
        var history = History()

        // act
        history.record(usage)

        // assert
        #expect(history.last[usage.provider] != nil)
        #expect(history.points.isEmpty)
    }

    // MARK: add

    @Test func addSkipsAPointOfTheSameProviderLessThanOneSecondFromAnExistingOne() {
        // arrange
        var history = History()
        history.add(Factories.point(.codex, at: t0))

        // act
        history.add(Factories.point(.codex, at: t0 + 0.999))

        // assert
        #expect(history.points.count == 1)
    }

    @Test(arguments: [
        Factories.point(.codex, at: Fixed.t0 + 1),
        Factories.point(.claude, at: Fixed.t0),
    ])
    func addKeepsAPointExactlyOneSecondApartAndAPointOfTheOtherProviderAtTheSameTime(new: HistoryPoint) {
        // arrange
        var history = History()
        history.add(Factories.point(.codex, at: t0))

        // act
        history.add(new)

        // assert
        #expect(history.points.count == 2)
    }

    @Test func addKeepsPointsSortedByTimeWhenAnOlderPointIsBackfilled() {
        // arrange
        var history = History()
        history.add(Factories.point(at: t0))
        history.add(Factories.point(at: t0 + 7200))

        // act
        history.add(Factories.point(at: t0 + 3600))

        // assert
        #expect(history.points.map(\.at) == [t0, t0 + 3600, t0 + 7200])
    }

    @Test func addPrunesPointsOlderThan60DaysBeforeTheAddedPointAndKeepsOneExactly60DaysOld() {
        // arrange
        var history = History()
        history.add(Factories.point(at: t0 - 60 * day - 1))
        history.add(Factories.point(at: t0 - 60 * day))

        // act
        history.add(Factories.point(at: t0))

        // assert
        #expect(history.points.map(\.at) == [t0 - 60 * day, t0])
    }

    // MARK: windows

    @Test func windowsUsesTheLatestResetOfAGroupAsResetsAtAndStartAndIgnoresOtherProviders() {
        // arrange
        let reset = t0
        var history = History()
        history.add(Factories.point(.claude, at: t0 - 100, resetsAt: reset + 1))
        history.add(Factories.point(.claude, at: t0 - 50, resetsAt: reset - 2))
        history.add(Factories.point(.codex, at: t0 - 75, resetsAt: reset))

        // act
        let windows = history.windows(.claude)

        // assert
        #expect(windows.count == 1)
        #expect(windows[0].resetsAt == reset + 1)
        #expect(windows[0].start == reset + 1 - 7 * day)
        #expect(windows[0].points.map(\.at) == [t0 - 100, t0 - 50])
    }

    @Test(arguments: [
        (3599.0, [3599.0]),
        (3600.0, [0.0, 3600.0]),
        (3601.0, [0.0, 3601.0]),
    ])
    func windowsGroupsResetsLessThanAnHourApartAndSplitsThemAtOneHour(offset: Double, expected: [Double]) {
        // arrange
        let reset = t0 + day
        let history = Factories.history(resets: [reset, reset + offset])

        // act
        let windows = history.windows(.claude)

        // assert
        #expect(windows.map(\.resetsAt) == expected.map { reset + $0 })
        #expect(windows.map(\.points.count).reduce(0, +) == 2)
    }

    @Test func windowsChainsResetsThatDriftLessThanAnHourStepByStepIntoOneWindow() {
        // arrange
        let reset = t0 + day
        let history = Factories.history(resets: [reset, reset + 3000, reset + 6000])

        // act
        let windows = history.windows(.claude)

        // assert
        #expect(windows.count == 1)
        #expect(windows[0].resetsAt == reset + 6000)
        #expect(windows[0].points.count == 3)
    }

    @Test func windowsReturnsSeparateWeeksOldestFirstWithTheirPointsSortedByTime() {
        // arrange
        let reset = t0
        var history = History()
        history.points = [
            Factories.point(at: t0 + 10, resetsAt: reset + 7 * day),
            Factories.point(at: t0 - 20, resetsAt: reset),
            Factories.point(at: t0 - 50, resetsAt: reset),
            Factories.point(at: t0 + 30, resetsAt: reset + 7 * day),
        ]

        // act
        let windows = history.windows(.claude, windowSeconds: 7 * day)

        // assert
        #expect(windows.map(\.resetsAt) == [reset, reset + 7 * day])
        #expect(windows.map { $0.points.map(\.at) } == [[t0 - 50, t0 - 20], [t0 + 10, t0 + 30]])
    }

    // MARK: HistoryFile

    @Test func saveThenLoadReturnsTheSamePointsAndLastUsage() throws {
        // arrange
        let dir = try Factories.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = HistoryFile(url: dir.appendingPathComponent("sub/history.json"))
        var history = History()
        history.record(Factories.usage(.claude, fetchedAt: t0, limits: [Factories.namedLimit(id: Limit.weeklyID, usedPercent: 30, resetsAt: t0 + day)]))
        history.record(Factories.usage(.codex, fetchedAt: t0 + 60, limits: [Factories.namedLimit(id: Limit.weeklyID, usedPercent: 55, resetsAt: t0 + 2 * day)]))

        // act
        try file.save(history)
        let loaded = file.load()

        // assert
        #expect(loaded.points == history.points)
        #expect(loaded.last[.claude]?.limits == history.last[.claude]?.limits)
        #expect(loaded.last[.codex]?.limits == history.last[.codex]?.limits)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sub").path))
    }

    @Test func loadReturnsEmptyHistoryAndWritesNoBackupWhenTheFileIsMissing() throws {
        // arrange
        let dir = try Factories.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = HistoryFile(url: dir.appendingPathComponent("history.json"))

        // act
        let loaded = file.load()

        // assert
        #expect(loaded.points.isEmpty)
        #expect(loaded.last.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.url.appendingPathExtension("bak").path))
    }

    @Test func loadMovesAFileThatDoesNotDecodeToTheBackupReplacingAnOlderBackup() throws {
        // arrange
        let dir = try Factories.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = HistoryFile(url: dir.appendingPathComponent("history.json"))
        let backup = file.url.appendingPathExtension("bak")
        try Data("not json".utf8).write(to: file.url)
        try Data("old backup".utf8).write(to: backup)

        // act
        let loaded = file.load()

        // assert
        #expect(loaded.points.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not json")
    }

    // MARK: CodexHistory.point

    @Test func codexPointReadsTheWeeklyWindowFromASessionLogLine() throws {
        // arrange
        let r1 = Fixed.reset1
        let r2 = Fixed.reset2
        let line = Factories.codexLogLine(
            timestamp: "2027-01-15T08:00:00.123Z",
            primary: Factories.codexLogWindow(minutes: 300, used: 10, resetsAt: r1),
            secondary: Factories.codexLogWindow(minutes: 10080, used: 55, resetsAt: r2))

        // act
        let point = try #require(CodexHistory.point(fromLogLine: line))

        // assert
        #expect(point.provider == .codex)
        #expect(point.at == Factories.iso("2027-01-15T08:00:00Z"))
        #expect(point.usedPercent == 55)
        #expect(point.resetsAt == Date(timeIntervalSince1970: r2))
    }

    @Test(arguments: [
        (primary: 8640.0, secondary: nil as Double?, expectedUsed: 33 as Double?),
        (primary: 8639.0, secondary: nil, expectedUsed: nil),
        (primary: 10080.0, secondary: 300.0, expectedUsed: 33),
        (primary: 10080.0, secondary: 10080.0, expectedUsed: 5),
    ])
    func codexPointUsesPrimaryWhenOnlyPrimaryIsAWeekLongAtTheSixDayBoundary(primary: Double, secondary: Double?, expectedUsed: Double?) {
        // arrange
        let line = Factories.codexLogLine(
            timestamp: "2027-01-15T08:00:00Z",
            primary: Factories.codexLogWindow(minutes: primary, used: 33, resetsAt: Fixed.reset1),
            secondary: secondary.map { Factories.codexLogWindow(minutes: $0, used: 5, resetsAt: Fixed.reset2) })

        // act
        let point = CodexHistory.point(fromLogLine: line)

        // assert
        #expect(point?.usedPercent == expectedUsed)
    }

    @Test(arguments: [
        Factories.codexLogLine(primary: Factories.codexLogWindow(minutes: 10080, used: 10, resetsAt: Fixed.reset1)),
        Factories.text(Factories.json(["timestamp": "2027-01-15T08:00:00Z", "payload": [:] as [String: Any]])),
        "not json",
    ])
    func codexPointReturnsNilWithoutATimestampOrRateLimits(line: String) {
        // act
        let point = CodexHistory.point(fromLogLine: line)

        // assert
        #expect(point == nil)
    }
}
