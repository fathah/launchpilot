import Foundation

nonisolated struct ProcessSpec: Sendable {
    let label: String
    let executable: String
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]?

    init(
        label: String,
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil
    ) {
        self.label = label
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

nonisolated enum LogStream: Sendable {
    case stdout
    case stderr
}

nonisolated struct LogLine: Sendable {
    let stream: LogStream
    let text: String
    let timestamp: Date
}

nonisolated enum ProcessEvent: Sendable {
    case started(pid: Int32, resolvedPath: String, commandLine: String)
    case log(LogLine)
    case exited(code: Int32)
    case failed(message: String)
    case cancelled
}

nonisolated enum ProcessRunnerError: Error, LocalizedError {
    case executableNotFound(String, searchedPath: String)
    case workingDirectoryMissing(URL)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name, let path):
            return "Could not find '\(name)' on PATH. Searched: \(path)"
        case .workingDirectoryMissing(let url):
            return "Working directory does not exist: \(url.path)"
        }
    }
}

nonisolated enum ProcessRunner {
    static func run(_ spec: ProcessSpec, cancellation: ProcessCancellation? = nil) -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            Task.detached {
                do {
                    let env = await EnvironmentResolver.shared.environment(merging: spec.environment)
                    let resolvedPath = try resolveExecutable(spec.executable, env: env)

                    guard FileManager.default.fileExists(atPath: spec.workingDirectory.path) else {
                        continuation.yield(.failed(message: ProcessRunnerError.workingDirectoryMissing(spec.workingDirectory).localizedDescription))
                        continuation.finish()
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: resolvedPath)
                    process.arguments = spec.arguments
                    process.currentDirectoryURL = spec.workingDirectory
                    process.environment = env

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    var stdoutBuffer = ""
                    var stderrBuffer = ""

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                        stdoutBuffer += text
                        while let newlineIdx = stdoutBuffer.firstIndex(of: "\n") {
                            let line = String(stdoutBuffer[..<newlineIdx])
                            stdoutBuffer.removeSubrange(...newlineIdx)
                            continuation.yield(.log(LogLine(stream: .stdout, text: line, timestamp: Date())))
                        }
                    }

                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                        stderrBuffer += text
                        while let newlineIdx = stderrBuffer.firstIndex(of: "\n") {
                            let line = String(stderrBuffer[..<newlineIdx])
                            stderrBuffer.removeSubrange(...newlineIdx)
                            continuation.yield(.log(LogLine(stream: .stderr, text: line, timestamp: Date())))
                        }
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.yield(.failed(message: error.localizedDescription))
                        continuation.finish()
                        return
                    }

                    let commandLine = ([resolvedPath] + spec.arguments).map(shellQuote).joined(separator: " ")
                    continuation.yield(.started(pid: process.processIdentifier, resolvedPath: resolvedPath, commandLine: commandLine))

                    if let cancellation {
                        await cancellation.attach(process: process)
                    }

                    process.waitUntilExit()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    if !stdoutBuffer.isEmpty {
                        continuation.yield(.log(LogLine(stream: .stdout, text: stdoutBuffer, timestamp: Date())))
                    }
                    if !stderrBuffer.isEmpty {
                        continuation.yield(.log(LogLine(stream: .stderr, text: stderrBuffer, timestamp: Date())))
                    }

                    let cancelled = await cancellation?.wasCancelled ?? false
                    if cancelled {
                        continuation.yield(.cancelled)
                    } else {
                        continuation.yield(.exited(code: process.terminationStatus))
                    }
                    continuation.finish()
                } catch let runnerError as ProcessRunnerError {
                    continuation.yield(.failed(message: runnerError.localizedDescription))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    private static func resolveExecutable(_ name: String, env: [String: String]) throws -> String {
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if name.hasPrefix("/") || name.hasPrefix("./") || name.hasPrefix("../") {
            let url = URL(fileURLWithPath: name)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ProcessRunnerError.executableNotFound(name, searchedPath: path)
            }
            return url.path
        }
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ProcessRunnerError.executableNotFound(name, searchedPath: path)
    }

    private static func shellQuote(_ arg: String) -> String {
        if arg.range(of: "[^A-Za-z0-9_./=-]", options: .regularExpression) == nil {
            return arg
        }
        let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

actor ProcessCancellation {
    private var process: Process?
    private(set) var wasCancelled: Bool = false

    func attach(process: Process) {
        self.process = process
    }

    func cancel() {
        guard !wasCancelled else { return }
        wasCancelled = true
        process?.terminate()
    }
}
