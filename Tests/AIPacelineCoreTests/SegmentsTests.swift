import Foundation
import Testing
@testable import AIPacelineCore

@Suite struct SegmentsTests {
    let t0 = Fixed.t0
    let gap: TimeInterval = 3 * 3600
    let overGap: TimeInterval = 3 * 3600 + 1
    let step: TimeInterval = 60
    let dayAhead: TimeInterval = 86400
    let justPast: TimeInterval = -60

    var openWindowReset: Date { t0.addingTimeInterval(dayAhead) }
    var pastReset: Date { t0.addingTimeInterval(justPast) }

    @Test func splitReturnsNoSegmentsForAnEmptyLine() {
        // arrange
        let points: [ChartPoint] = []

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.isEmpty)
    }

    @Test func splitKeepsASinglePointAsOneSolidSegment() {
        // arrange
        let points = Factories.chartLine(gaps: [])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.count == 1)
        #expect(result[0].dashed == false)
        #expect(result[0].points.count == 1)
    }

    @Test func splitKeepsOneSolidSegmentWhenGapsEqualMaxGapExactly() {
        // arrange
        let points = Factories.chartLine(gaps: [gap, gap])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.count == 1)
        #expect(result[0].dashed == false)
        #expect(result[0].points.count == 3)
    }

    @Test func splitBridgesAGapOneSecondAboveMaxGapWithADashedSegmentBetweenTwoSolidRuns() {
        // arrange
        let points = Factories.chartLine(gaps: [step, overGap, step])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.map(\.dashed) == [false, true, false])
        #expect(result[0].points == [points[0], points[1]])
        #expect(result[1].points == [points[1], points[2]])
        #expect(result[2].points == [points[2], points[3]])
    }

    @Test func splitGivesSegmentsUniqueSequentialIds() {
        // arrange
        let points = Factories.chartLine(gaps: [step, overGap, step, overGap, step])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.count == 5)
        #expect(result.map(\.id) == Array(0..<result.count))
    }

    @Test func splitDrawsTheLinkFromALonePointToARunOfTwoSolid() {
        // arrange
        let points = Factories.chartLine(gaps: [overGap, step])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.map(\.dashed) == [false, false])
        #expect(result[0].points == [points[0], points[1]])
        #expect(result[1].points == [points[1], points[2]])
        #expect(result.allSatisfy { $0.points.count >= 2 })
    }

    @Test func splitDrawsTheLinkFromARunOfTwoToALonePointSolid() {
        // arrange
        let points = Factories.chartLine(gaps: [step, overGap])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.map(\.dashed) == [false, false])
        #expect(result[0].points == [points[0], points[1]])
        #expect(result[1].points == [points[1], points[2]])
    }

    @Test func splitDrawsOneSolidLinkBetweenTwoLonePoints() {
        // arrange
        let points = Factories.chartLine(gaps: [overGap])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.count == 1)
        #expect(result[0].dashed == false)
        #expect(result[0].points == [points[0], points[1]])
    }

    @Test func splitDrawsBothLinksAroundALonePointBetweenTwoRunsSolid() {
        // arrange
        let points = Factories.chartLine(gaps: [step, overGap, overGap, step])

        // act
        let result = Segments.split(points, maxGap: gap)

        // assert
        #expect(result.map(\.points) == [[points[0], points[1]], [points[1], points[2]],
                                         [points[2], points[3]], [points[3], points[4]]])
        #expect(result.map(\.dashed) == [false, false, false, false])
        #expect(result.map(\.id) == [0, 1, 2, 3])
    }

    @Test func leftLineIsEmptyForAWindowWithoutPoints() {
        // arrange
        let window = Factories.window(resetsAt: openWindowReset, points: [])

        // act
        let result = window.leftLine(now: t0)

        // assert
        #expect(result.isEmpty)
    }

    @Test func leftLineStartsAt100OnTheWindowStartAndMapsEachPointTo100MinusUsed() {
        // arrange
        let a = t0.addingTimeInterval(-7200), b = t0.addingTimeInterval(-3600)
        let window = Factories.window(resetsAt: openWindowReset, points: [
            Factories.historyPoint(at: a, usedPercent: 10),
            Factories.historyPoint(at: b, usedPercent: 35),
        ])

        // act
        let result = window.leftLine(now: t0)

        // assert
        #expect(result == [
            ChartPoint(at: window.start, value: 100),
            ChartPoint(at: a, value: 90),
            ChartPoint(at: b, value: 65),
        ])
    }

    @Test func leftLineClampsUsedAbove100To0Left() {
        // arrange
        let at = t0.addingTimeInterval(justPast)
        let window = Factories.window(resetsAt: openWindowReset, points: [Factories.historyPoint(at: at, usedPercent: 120)])

        // act
        let result = window.leftLine(now: t0)

        // assert
        #expect(result.last == ChartPoint(at: at, value: 0))
    }

    @Test func leftLineHoldsTheLastValueUntilTheResetOnceTheWindowIsOver() {
        // arrange
        let reset = pastReset
        let window = Factories.window(resetsAt: reset, points: [Factories.historyPoint(at: t0.addingTimeInterval(-3600), usedPercent: 70, resetsAt: reset)])

        // act
        let result = window.leftLine(now: t0)

        // assert
        #expect(result.last == ChartPoint(at: reset, value: 30))
    }

    @Test(arguments: [0.0, 3600.0])
    func leftLineAddsNoHoldPointWhileTheWindowIsStillOpen(resetOffset: Double) {
        // arrange
        let point = Factories.historyPoint(at: t0.addingTimeInterval(justPast), usedPercent: 40)
        let window = Factories.window(resetsAt: t0.addingTimeInterval(resetOffset), points: [point])

        // act
        let result = window.leftLine(now: t0)

        // assert
        #expect(result.count == window.points.count + 1)
        #expect(result.last == ChartPoint(at: point.at, value: 60))
    }
}
