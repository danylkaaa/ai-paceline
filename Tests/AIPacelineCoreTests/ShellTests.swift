import Foundation
import Testing
@testable import AIPacelineCore

@Suite struct ShellTests {
    @Test func aCommandThatOutlivesItsTimeoutThrows() async {
        // arrange
        let started = Date()

        // act
        let error = await #expect(throws: Shell.TimedOut.self) { try await Shell.run("/bin/sleep", ["30"], timeout: 0.5) }

        // assert
        #expect(error != nil)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
