import Testing
import Foundation
@testable import launchpilot

struct PackageManagerTests {

    private func makeTempProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-pm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    @Test func detectsPnpm() throws {
        let dir = try makeTempProject(["pnpm-lock.yaml": "lockfileVersion: 6.0\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .pnpm)
    }

    @Test func detectsBunBinaryLockfile() throws {
        let dir = try makeTempProject(["bun.lockb": ""])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .bun)
    }

    @Test func detectsBunTextLockfile() throws {
        let dir = try makeTempProject(["bun.lock": "{}\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .bun)
    }

    @Test func detectsYarn() throws {
        let dir = try makeTempProject(["yarn.lock": "# yarn lockfile v1\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .yarn)
    }

    @Test func detectsNpm() throws {
        let dir = try makeTempProject(["package-lock.json": "{}\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .npm)
    }

    @Test func bunWinsOverOtherLockfiles() throws {
        // If a project has both bun.lockb and yarn.lock (legacy), prefer bun.
        let dir = try makeTempProject([
            "bun.lockb": "",
            "yarn.lock": "# yarn lockfile v1\n"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .bun)
    }

    @Test func parsesPackageManagerField() throws {
        let dir = try makeTempProject([
            "package.json": #"{ "name": "x", "packageManager": "pnpm@9.4.0" }"#
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == .pnpm)
    }

    @Test func returnsNilWhenNoSignals() throws {
        let dir = try makeTempProject([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PackageManager.detect(at: dir) == nil)
    }
}
