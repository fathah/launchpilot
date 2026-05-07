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

    @Test func resolvesRelativeExecutableAgainstWorkingDirectory() async throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("launchpilot-relexec-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let script = tmp.appendingPathComponent("hello.sh")
        try "#!/bin/sh\necho relative-ok\n".write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let spec = ProcessSpec(
            label: "./hello.sh",
            executable: "./hello.sh",
            arguments: [],
            workingDirectory: tmp
        )

        var collected: [String] = []
        var exitCode: Int32?
        for await event in ProcessRunner.run(spec) {
            switch event {
            case .log(let line): collected.append(line.text)
            case .exited(let code): exitCode = code
            case .failed(let msg): Issue.record("unexpected failure: \(msg)")
            default: break
            }
        }

        #expect(exitCode == 0)
        #expect(collected.contains("relative-ok"))
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
