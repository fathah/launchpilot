import Testing
import Foundation
@testable import launchpilot

struct ProcessRunnerTests {

    @Test func runsEchoAndCapturesStdout() async throws {
        let spec = ProcessSpec(
            label: "echo",
            executable: "/bin/echo",
            arguments: ["hello", "launchpilot"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        var collected: [String] = []
        var exitCode: Int32?
        var didStart = false

        for await event in ProcessRunner.run(spec) {
            switch event {
            case .started: didStart = true
            case .log(let line): collected.append(line.text)
            case .exited(let code): exitCode = code
            case .failed(let msg): Issue.record("unexpected failure: \(msg)")
            case .cancelled: Issue.record("unexpected cancellation")
            }
        }

        #expect(didStart)
        #expect(exitCode == 0)
        #expect(collected.contains("hello launchpilot"))
    }

    @Test func reportsNonZeroExit() async throws {
        let spec = ProcessSpec(
            label: "false",
            executable: "/usr/bin/false",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        var exitCode: Int32?
        for await event in ProcessRunner.run(spec) {
            if case .exited(let code) = event { exitCode = code }
        }
        #expect(exitCode != nil)
        #expect(exitCode != 0)
    }

    @Test func reportsExecutableNotFound() async throws {
        let spec = ProcessSpec(
            label: "missing",
            executable: "definitely-not-a-real-binary-xyz",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        var failure: String?
        for await event in ProcessRunner.run(spec) {
            if case .failed(let msg) = event { failure = msg }
        }
        #expect(failure != nil)
    }
}
