import Foundation
import Testing
@testable import AIPacelineCore

@Suite struct PaceTests {
    let t0 = Fixed.t0

    @Test func returnsNilWhenTheLimitHasNoResetTime() {
        // arrange
        let limit = Factories.limit(usedPercent: 40, resetsAt: nil)

        // act
        let result = Pace.of(limit, now: t0)

        // assert
        #expect(result == nil)
    }

    @Test func returnsNilWhenWindowSecondsIsZero() {
        // arrange
        let limit = Factories.limit(usedPercent: 40, windowSeconds: 0)

        // act
        let result = Pace.of(limit, now: t0)

        // assert
        #expect(result == nil)
    }

    @Test func expects50AndReportsPlus20DeltaAtHalfTheWindowWith70Used() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 70)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.expectedPercent == 50)
        #expect(result.deltaPercent == 20)
    }

    @Test func predictsTheRunOutTimeWhenTheCurrentRateEmptiesTheLimitBeforeReset() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 80)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.runsOutAt == t0.addingTimeInterval(25))
    }

    @Test func reportsNoRunOutWhenTheProjectionLandsExactlyOnTheReset() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 50)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.runsOutAt == nil)
    }

    @Test func reportsNoRunOutWhenTheLimitLastsPastReset() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 30)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.runsOutAt == nil)
        #expect(result.deltaPercent == -20)
    }

    @Test(arguments: [100.0, 120.0])
    func reportsRunOutNowWhenUsageIsAt100OrAbove(usedPercent: Double) throws {
        // arrange
        let limit = Factories.limit(usedPercent: usedPercent)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.runsOutAt == t0)
    }

    @Test func reportsNoRunOutAtZeroUsed() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 0)

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.runsOutAt == nil)
        #expect(result.expectedPercent == 50)
    }

    @Test func clampsExpectedTo0WhenNowIsBeforeTheWindowStart() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 10, resetsAt: t0.addingTimeInterval(300))

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.expectedPercent == 0)
        #expect(result.runsOutAt == nil)
    }

    @Test func clampsExpectedTo100WhenNowIsAfterTheReset() throws {
        // arrange
        let limit = Factories.limit(usedPercent: 60, resetsAt: t0.addingTimeInterval(-50))

        // act
        let result = try #require(Pace.of(limit, now: t0))

        // assert
        #expect(result.expectedPercent == 100)
        #expect(result.deltaPercent == -40)
    }
}
