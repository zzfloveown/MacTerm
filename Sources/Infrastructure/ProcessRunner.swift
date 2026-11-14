import Foundation
import OSLog

public enum AppLog {
    public static let storage = Logger(subsystem: "com.macterm.app", category: "storage")
}

/// 在后台执行系统工具，通过临时文件接收输出，避免 stdout/stderr 管道互相阻塞。
public enum ProcessRunner {
    public struct Result: Sendable {
        public let output: Data
        public let diagnostics: Data
        public let status: Int32
        public var text: String { String(decoding: output, as: UTF8.self) }
    }

    public static func run(_ executable: String, _ args: [String], input: Data? = nil) async throws -> Result {
        let execution = Execution()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try execution.run(executable, args, input: input)
            }.value
        } onCancel: {
            execution.cancel()
        }
    }

    private final class Execution: @unchecked Sendable {
        private let lock = NSLock()
        private let process = Process()
        private var cancelled = false

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if process.isRunning { process.terminate() }
        }

        func run(_ executable: String, _ args: [String], input: Data?) throws -> Result {
            let manager = FileManager.default
            let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: folder) }
            let stdout = folder.appendingPathComponent("stdout")
            let stderr = folder.appendingPathComponent("stderr")
            let stdin = folder.appendingPathComponent("stdin")
            try Data().write(to: stdout)
            try Data().write(to: stderr)
            try (input ?? Data()).write(to: stdin)

            let out = try FileHandle(forWritingTo: stdout)
            let err = try FileHandle(forWritingTo: stderr)
            let source = try FileHandle(forReadingFrom: stdin)
            defer {
                try? out.close()
                try? err.close()
                try? source.close()
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardOutput = out
            process.standardError = err
            process.standardInput = source
            process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "en_US.UTF-8"]) { _, value in value }
            try launch()
            process.waitUntilExit()
            try checkCancellation()
            return try Result(output: Data(contentsOf: stdout), diagnostics: Data(contentsOf: stderr),
                              status: process.terminationStatus)
        }

        private func launch() throws {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { throw CancellationError() }
            try process.run()
        }

        private func checkCancellation() throws {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { throw CancellationError() }
        }
    }
}
