import Foundation

public enum Shell {
    public struct Failed: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var description: String { "exit \(status): \(stderr.prefix(300))" }
    }

    public struct TimedOut: Error, CustomStringConvertible {
        public var seconds: TimeInterval
        public var description: String { "no answer after \(Int(seconds)) s" }
    }

    /// Runs a program and returns its standard output; throws on a non-zero exit or after `timeout`.
    /// Waits through `terminationHandler`: `waitUntilExit` on a pool thread can miss the exit and block forever.
    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 300) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let finish = Once(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            let done = DispatchGroup()
            let output = Output()
            done.enter()
            process.terminationHandler = { _ in done.leave() }
            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }
            for (pipe, isOut) in [(out, true), (err, false)] {
                done.enter()
                DispatchQueue.global().async {
                    output.set(pipe.fileHandleForReading.readDataToEndOfFile(), isOut: isOut)
                    done.leave()
                }
            }
            done.notify(queue: .global()) {
                guard process.terminationStatus == 0 else {
                    finish(.failure(Failed(status: process.terminationStatus,
                                           stderr: String(decoding: output.err, as: UTF8.self))))
                    return
                }
                finish(.success(String(decoding: output.out, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if finish(.failure(TimedOut(seconds: timeout))), process.isRunning { process.terminate() }
            }
        }
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data: (out: Data, err: Data) = (Data(), Data())
        var out: Data { lock.withLock { data.out } }
        var err: Data { lock.withLock { data.err } }
        func set(_ value: Data, isOut: Bool) {
            lock.withLock { if isOut { data.out = value } else { data.err = value } }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Error>?
        init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }

        /// Resumes the first time only; returns whether this call did it.
        @discardableResult
        func callAsFunction(_ result: Result<String, Error>) -> Bool {
            guard let c = lock.withLock({ defer { continuation = nil }; return continuation }) else { return false }
            c.resume(with: result)
            return true
        }
    }
}
