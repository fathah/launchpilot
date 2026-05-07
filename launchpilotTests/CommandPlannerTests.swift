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
        let upload = plan.steps.last!.processSpec!
        #expect(upload.executable == "/bin/sh")
        let script = upload.arguments.last ?? ""
        #expect(script.contains("altool"))
        #expect(script.contains("--apiKey \"KEY123\""))
        #expect(script.contains("--apiIssuer \"11111111-2222-3333-4444-555555555555\""))
        #expect(upload.workingDirectory.path == tempDir.path)
    }

    @Test func nativeAndroidPlanOmitsSigningWhenNoKeystoreRef() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        let config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        let plan = try CommandPlanner.plan(action: .buildAndroidAAB, project: project, config: config)

        let gradle = plan.steps.first(where: { $0.label.contains("gradlew") })?.processSpec
        #expect(gradle != nil)
        #expect(gradle?.arguments.contains(where: { $0.hasPrefix("-PLP_KEYSTORE_FILE") }) == false)
    }

    @Test func nativeAndroidPlanInjectsSigningWhenKeystorePresent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        var config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        config.apps.android?.signing = ProjectConfig.AndroidSigning(keystoreRef: "release_keystore")

        let credential = Credential(
            ref: "release_keystore",
            displayName: "Release",
            secret: .androidKeystore(AndroidKeystoreSecret(
                keystorePath: "/Users/example/release.jks",
                keystorePassword: "store-pass",
                keyAlias: "release",
                keyPassword: "key-pass"
            ))
        )

        let plan = try CommandPlanner.plan(
            action: .buildAndroidAAB,
            project: project,
            config: config,
            credentials: ["release_keystore": credential]
        )
        let gradle = plan.steps.first(where: { $0.label.contains("gradlew") })?.processSpec
        #expect(gradle != nil)
        let args = gradle?.arguments ?? []
        #expect(args.contains("-PLP_KEYSTORE_FILE=/Users/example/release.jks"))
        #expect(args.contains("-PLP_KEYSTORE_PASSWORD=store-pass"))
        #expect(args.contains("-PLP_KEY_ALIAS=release"))
        #expect(args.contains("-PLP_KEY_PASSWORD=key-pass"))
    }

    @Test func nativeAndroidPlanSkipsSigningWhenCredentialMissing() throws {
        // keystore_ref is set, but no matching credential — we should still build,
        // just without signing (so the build fails predictably with a gradle error).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        var config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        config.apps.android?.signing = ProjectConfig.AndroidSigning(keystoreRef: "missing_ref")

        let plan = try CommandPlanner.plan(
            action: .buildAndroidAAB,
            project: project,
            config: config,
            credentials: [:]
        )
        let gradle = plan.steps.first(where: { $0.label.contains("gradlew") })?.processSpec
        #expect(gradle?.arguments.contains(where: { $0.hasPrefix("-PLP_KEYSTORE_FILE") }) == false)
    }

    @Test func flutterAndroidInjectsSigningProperties() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .flutter)
        var config = ProjectConfig.defaults(name: "App", framework: .flutter)
        config.apps.android?.signing = ProjectConfig.AndroidSigning(keystoreRef: "ks")

        let credential = Credential(
            ref: "ks",
            displayName: "Release",
            secret: .androidKeystore(AndroidKeystoreSecret(
                keystorePath: "/keys/r.jks",
                keystorePassword: "p1",
                keyAlias: "a1",
                keyPassword: "p2"
            ))
        )

        let plan = try CommandPlanner.plan(
            action: .buildAndroidAAB,
            project: project,
            config: config,
            credentials: ["ks": credential]
        )
        let appbundle = plan.steps.first(where: { $0.label.contains("appbundle") })?.processSpec
        #expect(appbundle?.arguments.contains("-PLP_KEYSTORE_FILE=/keys/r.jks") == true)
    }

    @Test func googlePlayPlanFailsWithoutCredentialRef() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        var config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        config.apps.android?.packageName = "org.example.app"

        #expect(throws: PlanningError.self) {
            _ = try CommandPlanner.plan(action: .publishGooglePlay, project: project, config: config)
        }
    }

    @Test func googlePlayPlanFailsWithoutPackageName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        var config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        config.publishing.googlePlay = ProjectConfig.GooglePlayPublishing(
            enabled: true, serviceAccountRef: "play_main", defaultTrack: "internal"
        )
        let credential = Credential(
            ref: "play_main",
            displayName: "Play",
            secret: .googlePlayServiceAccount(GooglePlayServiceAccountSecret(
                jsonContents: "{}", clientEmail: nil
            ))
        )
        #expect(throws: PlanningError.self) {
            _ = try CommandPlanner.plan(
                action: .publishGooglePlay,
                project: project,
                config: config,
                credentials: ["play_main": credential]
            )
        }
    }

    @Test func googlePlayPlanIncludesBuildAndUploadSteps() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = Project(name: "App", path: dir.path, framework: .nativeAndroid)
        var config = ProjectConfig.defaults(name: "App", framework: .nativeAndroid)
        config.apps.android?.packageName = "org.example.app"
        config.publishing.googlePlay = ProjectConfig.GooglePlayPublishing(
            enabled: true, serviceAccountRef: "play_main", defaultTrack: "alpha"
        )
        let credential = Credential(
            ref: "play_main",
            displayName: "Play",
            secret: .googlePlayServiceAccount(GooglePlayServiceAccountSecret(
                jsonContents: #"{"client_email":"x@y.iam.gserviceaccount.com"}"#,
                clientEmail: "x@y.iam.gserviceaccount.com"
            ))
        )
        let plan = try CommandPlanner.plan(
            action: .publishGooglePlay,
            project: project,
            config: config,
            credentials: ["play_main": credential]
        )
        #expect(plan.steps.contains(where: { $0.label.contains("gradlew") }))
        #expect(plan.steps.last?.label.contains("Google Play") == true)
        #expect(plan.steps.last?.label.contains("alpha") == true)
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
