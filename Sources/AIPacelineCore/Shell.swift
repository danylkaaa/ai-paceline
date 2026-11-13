import Foundation

public enum Shell {
    public struct Failed: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var description: String { "exit \(status): \(stderr.prefix(300))" }
    }

    /// Runs a program off the main thread and returns its standard output; throws on a non-zero exit.
    public static func run(_ path: String, _ args: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            async let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = await errData
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw Failed(status: process.terminationStatus, stderr: String(decoding: stderr, as: UTF8.self))
            }
            return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
