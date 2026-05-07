import Testing
import Foundation
@testable import launchpilot

struct CommandPlannerTests {

    private func makeIOSProject() throws -> Project {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let proj = dir.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try "// stub".write(to: proj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        return Project(name: "App", path: dir.path, framework: .nativeIOS)
    }

    private func iosConfigWithPublishing(apiKeyRef: String?) -> ProjectConfig {
        var config = ProjectConfig.defaults(name: "App", framework: .nativeIOS)
        config.apps.ios?.scheme = "App"
        config.apps.ios?.bundleId = "org.example.app"
        config.apps.ios?.teamId = "TEAM12"
        config.publishing.apple = ProjectConfig.ApplePublishing(
            enabled: true,
            apiKeyRef: apiKeyRef,
            appId: nil
        )
        return config
    }

    @Test func testFlightPlanFailsWithoutCredentialRef() throws {
        let project = try makeIOSProject()
        defer { try? FileManager.default.removeItem(at: project.url) }

        let config = iosConfigWithPublishing(apiKeyRef: nil)
        #expect(throws: PlanningError.self) {
            _ = try CommandPlanner.plan(action: .publishTestFlight, project: project, config: config)
        }
    }

    @Test func testFlightPlanFailsWhenCredentialMissing() throws {
        let project = try makeIOSProject()
        defer { try? FileManager.default.removeItem(at: project.url) }

        let config = iosConfigWithPublishing(apiKeyRef: "missing_key")
        #expect(throws: PlanningError.self) {
            _ = try CommandPlanner.plan(
                action: .publishTestFlight,
                project: project,
                config: config,
                credentials: [:]
            )
        }
    }

    @Test func testFlightPlanIncludesArchiveExportAndUpload() throws {
        let project = try makeIOSProject()
        defer { try? FileManager.default.removeItem(at: project.url) }

        let config = iosConfigWithPublishing(apiKeyRef: "apple_main")
        let credential = Credential(
            ref: "apple_main",
            displayName: "Apple Main",
            secret: .appleAPIKey(AppleAPIKeySecret(
                keyId: "KEY123",
                issuerId: "11111111-2222-3333-4444-555555555555",
                teamId: "TEAM12",
                p8Contents: "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----"
            ))
        )

        let plan = try CommandPlanner.plan(
            action: .publishTestFlight,
            project: project,
            config: config,
            credentials: ["apple_main": credential]
        )
        defer { plan.cleanupPaths.forEach { try? FileManager.default.removeItem(at: $0) } }

        // Steps: archive, export, upload
        #expect(plan.steps.count >= 3)
        #expect(plan.steps.contains(where: { $0.label == "xcodebuild archive" }))
        #expect(plan.steps.contains(where: { $0.label == "xcodebuild -exportArchive" }))
        #expect(plan.steps.last?.label.contains("altool") == true)

        // Cleanup path was registered
        #expect(plan.cleanupPaths.count == 1)
        let tempDir = plan.cleanupPaths[0]

        // .p8 was staged at <tempdir>/private_keys/AuthKey_KEY123.p8
        let p8 = tempDir.appendingPathComponent("private_keys/AuthKey_KEY123.p8")
        #expect(FileManager.default.fileExists(atPath: p8.path))

        // Permissions are 0600
        if let attrs = try? FileManager.default.attributesOfItem(atPath: p8.path),
           let perms = attrs[.posixPermissions] as? NSNumber {
            #expect(perms.int16Value == 0o600)
        }

        // Upload step uses /bin/sh and references the IPA dir + altool
        let upload = plan.steps.last!
        #expect(upload.executable == "/bin/sh")
        let script = upload.arguments.last ?? ""
        #expect(script.contains("altool"))
        #expect(script.contains("--apiKey \"KEY123\""))
        #expect(script.contains("--apiIssuer \"11111111-2222-3333-4444-555555555555\""))
        #expect(upload.workingDirectory.path == tempDir.path)
    }

    @Test func testFlightRejectsAndroidOnlyFramework() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        let config = iosConfigWithPublishing(apiKeyRef: "apple_main")
        #expect(throws: PlanningError.self) {
            _ = try CommandPlanner.plan(
                action: .publishTestFlight,
                project: project,
                config: config,
                credentials: ["apple_main": Credential(
                    ref: "apple_main",
                    displayName: "Apple",
                    secret: .appleAPIKey(AppleAPIKeySecret(keyId: "K", issuerId: "I", teamId: nil, p8Contents: ""))
                )]
            )
        }
    }
}
