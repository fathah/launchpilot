import Foundation

/// A single step in a planned build.
///
/// Builds are normally a sequence of CLI invocations (`xcodebuild`, `gradlew`,
/// `flutter`), modelled as `.process` steps. Some steps need to do work that
/// can't be expressed as a subprocess — for example uploading to Google Play
/// using the Play Developer API. Those run as `.task` closures inside the app,
/// streaming log lines through `BuildTaskContext`.
indirect enum BuildStep: Sendable {
    case process(ProcessSpec)
    case task(label: String, run: @Sendable (BuildTaskContext) async -> BuildStepResult)

    var label: String {
        switch self {
        case .process(let spec): return spec.label
        case .task(let label, _): return label
        }
    }

    var processSpec: ProcessSpec? {
        if case .process(let spec) = self { return spec }
        return nil
    }
}

enum BuildStepResult: Sendable {
    case succeeded
    case failed(message: String)
    case cancelled
}

/// Hands a running task hooks into the live build session.
///
/// The closures route log writes to both the in-memory `BuildSession` (for the
/// live console) and the persisted log file. They're Sendable so the task body
/// is free to run off the main actor (e.g. for network I/O).
struct BuildTaskContext: Sendable {
    let log: @Sendable (LogLine) async -> Void
    let isCancelled: @Sendable () async -> Bool

    func emit(_ text: String, stream: LogStream = .stdout) async {
        await log(LogLine(stream: stream, text: text, timestamp: Date()))
    }
}
