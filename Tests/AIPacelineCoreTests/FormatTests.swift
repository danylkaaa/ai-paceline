import Foundation
import Testing
@testable import AIPacelineCore

@Suite struct FormatTests {
    let t0 = Fixed.t0

    static let shortCases: [(Int, String)] = [
        (59, "0m"),
        (59 * 60, "59m"),
        (3600, "1h"),
        (1439 * 60, "23h"),
        (86400, "1d"),
        (86399, "23h"),
        (2 * 86400 + 15 * 3600, "2d"),
    ]

    static let longCases: [(Int, String)] = [
        (2400, "40m"),
        (3600, "1h 0m"),
        (12_000, "3h 20m"),
        (86400, "1d 0h"),
        (2 * 86400 + 15 * 3600 + 59 * 60, "2d 15h"),
    ]

    struct RingCase: Sendable {
        let usedPercent: Double
        let stepIndex: Int
    }

    static let ringCases: [RingCase] = [
        RingCase(usedPercent: 49.9, stepIndex: 0),
        RingCase(usedPercent: 50, stepIndex: 1),
        RingCase(usedPercent: 79.9, stepIndex: 1),
        RingCase(usedPercent: 80, stepIndex: 2),
        RingCase(usedPercent: 100, stepIndex: 2),
    ]

    static let ringHex: [Provider: [UInt32]] = [
        .claude: [0xF2B48F, 0xD97757, 0xB83A1E],
        .codex: [0x8FD9CC, 0x2A9D8F, 0x12676B],
    ]

    @Test(arguments: shortCases)
    func shortResetTextRoundsDownToOneUnitAtEachBoundary(seconds: Int, expected: String) {
        // arrange
        let date = t0.addingTimeInterval(TimeInterval(seconds))

        // act
        let result = ResetText.short(until: date, now: t0)

        // assert
        #expect(result == expected)
    }

    @Test func shortAndLongResetTextShow0mWhenTheResetIsAlreadyPast() {
        // arrange
        let date = t0.addingTimeInterval(-600)

        // act
        let short = ResetText.short(until: date, now: t0)
        let long = ResetText.long(until: date, now: t0)

        // assert
        #expect(short == "0m")
        #expect(long == "0m")
    }

    @Test(arguments: longCases)
    func longResetTextShowsTwoUnitsAtEachBoundary(seconds: Int, expected: String) {
        // arrange
        let date = t0.addingTimeInterval(TimeInterval(seconds))

        // act
        let result = ResetText.long(until: date, now: t0)

        // assert
        #expect(result == expected)
    }

    @Test(arguments: [Provider.claude, Provider.codex], ringCases)
    func ringColorSwitchesFromLightToBaseAt50AndFromBaseToDeepAt80(provider: Provider, ring: RingCase) {
        // arrange
        let expected = RGB(hex: Self.ringHex[provider]![ring.stepIndex])

        // act
        let result = Palette.ring(provider, usedPercent: ring.usedPercent)

        // assert
        #expect(result == expected)
    }
}
