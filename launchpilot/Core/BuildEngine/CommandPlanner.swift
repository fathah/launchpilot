import Foundation

struct PlannedBuild: Sendable {
    let steps: [BuildStep]
    let expectedArtifacts: [PlannedArtifact]
    let cleanupPaths: [URL]

    init(steps: [BuildStep], expectedArtifacts: [PlannedArtifact], cleanupPaths: [URL] = []) {
        self.steps = steps
        self.expectedArtifacts = expectedArtifacts
        self.cleanupPaths = cleanupPaths
    }

    /// Convenience for plans that are entirely subprocess steps.
    init(processSteps: [ProcessSpec], expectedArtifacts: [PlannedArtifact], cleanupPaths: [URL] = []) {
        self.steps = processSteps.map { .process($0) }
        self.expectedArtifacts = expectedArtifacts
        self.cleanupPaths = cleanupPaths
    }
}

struct PlannedArtifact: Sendable {
    let name: String
    let type: BuildArtifact.ArtifactType
    let platform: Platform
    let relativePath: String
}

enum PlanningError: Error, LocalizedError {
    case unsupported(framework: Framework, action: BuildAction)
    case missing(String)
    case needsExpoPrebuild

    var errorDescription: String? {
        switch self {
        case .unsupported(let fw, let action):
            return "\(fw.displayName) does not support \(action.displayName) yet."
        case .missing(let what):
            return "Cannot start build: \(what)"
        case .needsExpoPrebuild:
            return "Expo project has no native folders yet. Run `npx expo prebuild` first."
        }
    }
}

enum CommandPlanner {
    static func plan(
        action: BuildAction,
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential] = [:]
    ) throws -> PlannedBuild {
        switch action {
        case .buildIOSIPA, .archiveOnly where project.framework.supportsIOS:
            return try planIOS(project: project, config: config)
        case .buildAndroidAAB, .archiveOnly:
            return try planAndroid(project: project, config: config, credentials: credentials, artifactType: .aab)
        case .buildAndroidAPK:
            return try planAndroid(project: project, config: config, credentials: credentials, artifactType: .apk)
        case .publishTestFlight, .publishAppStore:
            return try planAppleUpload(action: action, project: project, config: config, credentials: credentials)
        case .publishGooglePlay:
            return try planGooglePlayUpload(project: project, config: config, credentials: credentials)
        }
    }

    // MARK: - Google Play upload

    private static func planGooglePlayUpload(
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential]
    ) throws -> PlannedBuild {
        guard project.framework.supportsAndroid else {
            throw PlanningError.unsupported(framework: project.framework, action: .publishGooglePlay)
        }
        guard let ref = config.publishing.googlePlay?.serviceAccountRef, !ref.isEmpty else {
            throw PlanningError.missing("publishing.google_play.service_account_ref — pick a service account first.")
        }
        guard let credential = credentials[ref],
              case .googlePlayServiceAccount(let secret) = credential.secret else {
            throw PlanningError.missing("Google Play service account '\(ref)' is not stored. Add it under Credentials.")
        }
        guard let packageName = config.apps.android?.packageName, !packageName.isEmpty else {
            throw PlanningError.missing("apps.android.package_name")
        }
        let track = config.publishing.googlePlay?.defaultTrack ?? "internal"

        let aabPlan = try planAndroid(project: project, config: config, credentials: credentials, artifactType: .aab)
        let aabRelativePath = aabPlan.expectedArtifacts
            .first(where: { $0.type == .aab })?
            .relativePath ?? "build/app/outputs/bundle/release"
        let aabSearchDir = project.url.appendingPathComponent(aabRelativePath)
        let serviceAccountJSON = secret.jsonContents

        let upload = BuildStep.task(label: "Upload to Google Play (\(track))") { context in
            await context.emit("Looking for AAB in \(aabSearchDir.path)…")
            let aabURL: URL
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: aabSearchDir.path)
                guard let aabName = entries.first(where: { $0.hasSuffix(".aab") }) else {
                    return .failed(message: "No .aab found in \(aabSearchDir.path).")
                }
                aabURL = aabSearchDir.appendingPathComponent(aabName)
            } catch {
                return .failed(message: "Could not list \(aabSearchDir.path): \(error.localizedDescription)")
            }

            let request = PlayStorePublishRequest(
                packageName: packageName,
                track: track,
                aabPath: aabURL,
                releaseStatus: "draft"
            )

            do {
                _ = try await PlayStorePublisher.publish(
                    request: request,
                    serviceAccountJSON: serviceAccountJSON,
                    log: { text, stream in
                        await context.emit(text, stream: stream)
                    },
                    isCancelled: { await context.isCancelled() }
                )
                if await context.isCancelled() { return .cancelled }
                return .succeeded
            } catch PlayStorePublishError.cancelled {
                return .cancelled
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }

        return PlannedBuild(
            steps: aabPlan.steps + [upload],
            expectedArtifacts: aabPlan.expectedArtifacts,
            cleanupPaths: aabPlan.cleanupPaths
        )
    }

    // MARK: - Apple upload (TestFlight / App Store)

    private static func planAppleUpload(
        action: BuildAction,
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential]
    ) throws -> PlannedBuild {
        guard project.framework.supportsIOS else {
            throw PlanningError.unsupported(framework: project.framework, action: action)
        }
        guard let ref = config.publishing.apple?.apiKeyRef, !ref.isEmpty else {
            throw PlanningError.missing("publishing.apple.api_key_ref — pick an Apple credential first.")
        }
        guard let credential = credentials[ref],
              case .appleAPIKey(let secret) = credential.secret else {
            throw PlanningError.missing("Apple API key '\(ref)' is not stored. Add it under Credentials.")
        }

        let archivePlan = try planIOS(project: project, config: config)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchpilot-upload-\(UUID().uuidString)", isDirectory: true)
        let privateKeysDir = tempDir.appendingPathComponent("private_keys", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: privateKeysDir, withIntermediateDirectories: true)
            let p8URL = privateKeysDir.appendingPathComponent("AuthKey_\(secret.keyId).p8")
            try secret.p8Contents.write(to: p8URL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p8URL.path)
        } catch {
            throw PlanningError.missing("could not stage Apple API key: \(error.localizedDescription)")
        }

        let ipaDirRel = config.apps.ios?.build?.ipaOutputDir ?? "build/ios/ipa"
        let ipaDir = project.url.appendingPathComponent(ipaDirRel)
        let issuerEscaped = secret.issuerId.replacingOccurrences(of: "\"", with: "\\\"")
        let keyEscaped = secret.keyId.replacingOccurrences(of: "\"", with: "\\\"")
        let dirEscaped = ipaDir.path.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        set -e
        IPA=$(ls "\(dirEscaped)"/*.ipa 2>/dev/null | head -n 1)
        if [ -z "$IPA" ]; then
          echo "launchpilot: no .ipa found in \(dirEscaped). Did the export step run?" >&2
          exit 1
        fi
        echo "launchpilot: uploading $IPA"
        xcrun altool --upload-app --type ios -f "$IPA" --apiKey "\(keyEscaped)" --apiIssuer "\(issuerEscaped)"
        """

        let upload = ProcessSpec(
            label: "altool upload (App Store Connect)",
            executable: "/bin/sh",
            arguments: ["-c", script],
            workingDirectory: tempDir
        )

        return PlannedBuild(
            steps: archivePlan.steps + [.process(upload)],
            expectedArtifacts: archivePlan.expectedArtifacts,
            cleanupPaths: [tempDir]
        )
    }

    // MARK: - iOS

    private static func planIOS(project: Project, config: ProjectConfig) throws -> PlannedBuild {
        guard config.apps.ios?.enabled == true else {
            throw PlanningError.missing("iOS is not enabled in launchpilot.yaml")
        }
        switch project.framework {
        case .flutter:
            return try planFlutterIOS(project: project, config: config)
        case .nativeIOS:
            return try planNativeIOS(project: project, config: config)
        case .reactNative:
            return try planReactNativeIOS(project: project, config: config)
        case .expo:
            let iosDir = project.url.appendingPathComponent("ios")
            guard DetectionFS.isDirectory(iosDir) else { throw PlanningError.needsExpoPrebuild }
            return try planReactNativeIOS(project: project, config: config)
        case .nativeAndroid, .unknown:
            throw PlanningError.unsupported(framework: project.framework, action: .buildIOSIPA)
        }
    }

    private static func planFlutterIOS(project: Project, config: ProjectConfig) throws -> PlannedBuild {
        let cwd = project.url
        let exportMethod = config.apps.ios?.exportMethod ?? "app-store"
        let pubGet = ProcessSpec(
            label: "flutter pub get",
            executable: "flutter",
            arguments: ["pub", "get"],
            workingDirectory: cwd
        )
        let buildIPA = ProcessSpec(
            label: "flutter build ipa",
            executable: "flutter",
            arguments: ["build", "ipa", "--release", "--export-method=\(exportMethod)"],
            workingDirectory: cwd
        )
        return PlannedBuild(
            processSteps: [pubGet, buildIPA],
            expectedArtifacts: [
                PlannedArtifact(name: "App.xcarchive", type: .xcarchive, platform: .iOS, relativePath: "build/ios/archive"),
                PlannedArtifact(name: "App.ipa", type: .ipa, platform: .iOS, relativePath: "build/ios/ipa")
            ]
        )
    }

    private static func planNativeIOS(project: Project, config: ProjectConfig) throws -> PlannedBuild {
        let ios = config.apps.ios
        let scheme = ios?.scheme ?? ""
        guard !scheme.isEmpty else { throw PlanningError.missing("iOS scheme") }
        let configuration = ios?.configuration ?? "Release"
        let archiveRel = ios?.build?.archivePath ?? "build/ios/archive/App.xcarchive"
        let ipaDirRel = ios?.build?.ipaOutputDir ?? "build/ios/ipa"

        var args: [String] = ["archive"]
        if let workspace = ios?.workspace, !workspace.isEmpty {
            args.append(contentsOf: ["-workspace", workspace])
        } else if let xcodeProj = firstXcodeProject(in: project.url) {
            args.append(contentsOf: ["-project", xcodeProj])
        } else {
            throw PlanningError.missing("Xcode workspace or project")
        }
        args.append(contentsOf: [
            "-scheme", scheme,
            "-configuration", configuration,
            "-archivePath", archiveRel,
            "-allowProvisioningUpdates"
        ])

        let archive = ProcessSpec(
            label: "xcodebuild archive",
            executable: "xcodebuild",
            arguments: args,
            workingDirectory: project.url
        )

        let export = try makeExportSpec(
            project: project,
            config: config,
            archiveRel: archiveRel,
            ipaDirRel: ipaDirRel
        )

        return PlannedBuild(
            processSteps: [archive, export],
            expectedArtifacts: [
                PlannedArtifact(
                    name: URL(fileURLWithPath: archiveRel).lastPathComponent,
                    type: .xcarchive,
                    platform: .iOS,
                    relativePath: URL(fileURLWithPath: archiveRel).deletingLastPathComponent().relativePath
                ),
                PlannedArtifact(
                    name: "App.ipa",
                    type: .ipa,
                    platform: .iOS,
                    relativePath: ipaDirRel
                )
            ]
        )
    }

    private static func planReactNativeIOS(project: Project, config: ProjectConfig) throws -> PlannedBuild {
        let ios = config.apps.ios
        let scheme = ios?.scheme ?? defaultRNScheme(for: project) ?? ""
        guard !scheme.isEmpty else { throw PlanningError.missing("iOS scheme") }
        let configuration = ios?.configuration ?? "Release"
        let archiveRel = ios?.build?.archivePath ?? "ios/build/archive/App.xcarchive"
        let ipaDirRel = ios?.build?.ipaOutputDir ?? "ios/build/ipa"
        let iosDir = project.url.appendingPathComponent("ios")

        let pm = resolvePackageManager(project: project, config: config)
        let install = ProcessSpec(
            label: "\(pm.executable) install",
            executable: pm.executable,
            arguments: pm.installArguments,
            workingDirectory: project.url
        )
        let pod = ProcessSpec(
            label: "pod install",
            executable: "pod",
            arguments: ["install"],
            workingDirectory: iosDir
        )

        var archiveArgs: [String] = ["archive"]
        if let workspace = ios?.workspace, !workspace.isEmpty {
            archiveArgs.append(contentsOf: ["-workspace", workspace])
        } else if let ws = firstWorkspace(in: iosDir) {
            archiveArgs.append(contentsOf: ["-workspace", "ios/\(ws)"])
        } else if let xc = firstXcodeProject(in: iosDir) {
            archiveArgs.append(contentsOf: ["-project", "ios/\(xc)"])
        } else {
            throw PlanningError.missing("Xcode workspace or project")
        }
        archiveArgs.append(contentsOf: [
            "-scheme", scheme,
            "-configuration", configuration,
            "-archivePath", archiveRel,
            "-allowProvisioningUpdates"
        ])
        let archive = ProcessSpec(
            label: "xcodebuild archive",
            executable: "xcodebuild",
            arguments: archiveArgs,
            workingDirectory: project.url
        )

        let export = try makeExportSpec(
            project: project,
            config: config,
            archiveRel: archiveRel,
            ipaDirRel: ipaDirRel
        )

        return PlannedBuild(
            processSteps: [install, pod, archive, export],
            expectedArtifacts: [
                PlannedArtifact(
                    name: URL(fileURLWithPath: archiveRel).lastPathComponent,
                    type: .xcarchive,
                    platform: .iOS,
                    relativePath: URL(fileURLWithPath: archiveRel).deletingLastPathComponent().relativePath
                ),
                PlannedArtifact(
                    name: "App.ipa",
                    type: .ipa,
                    platform: .iOS,
                    relativePath: ipaDirRel
                )
            ]
        )
    }

    // MARK: - Export helpers

    private static func makeExportSpec(
        project: Project,
        config: ProjectConfig,
        archiveRel: String,
        ipaDirRel: String
    ) throws -> ProcessSpec {
        let exportPlistRel = "build/launchpilot/ExportOptions.plist"
        let plistURL = project.url.appendingPathComponent(exportPlistRel)
        let options = ExportOptionsWriter.from(config: config)
        do {
            try ExportOptionsWriter.write(at: plistURL, options: options)
        } catch {
            throw PlanningError.missing("could not write ExportOptions.plist: \(error.localizedDescription)")
        }
        return ProcessSpec(
            label: "xcodebuild -exportArchive",
            executable: "xcodebuild",
            arguments: [
                "-exportArchive",
                "-archivePath", archiveRel,
                "-exportPath", ipaDirRel,
                "-exportOptionsPlist", exportPlistRel,
                "-allowProvisioningUpdates"
            ],
            workingDirectory: project.url
        )
    }

    // MARK: - Android

    private static func planAndroid(
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential],
        artifactType: BuildArtifact.ArtifactType
    ) throws -> PlannedBuild {
        guard config.apps.android?.enabled == true else {
            throw PlanningError.missing("Android is not enabled in launchpilot.yaml")
        }
        let action: BuildAction = (artifactType == .apk) ? .buildAndroidAPK : .buildAndroidAAB
        switch project.framework {
        case .flutter:
            return planFlutterAndroid(project: project, config: config, credentials: credentials, artifactType: artifactType)
        case .reactNative:
            return planReactNativeAndroid(project: project, config: config, credentials: credentials, artifactType: artifactType)
        case .nativeAndroid:
            return planNativeAndroid(project: project, config: config, credentials: credentials, artifactType: artifactType)
        case .expo:
            let androidDir = project.url.appendingPathComponent("android")
            guard DetectionFS.isDirectory(androidDir) else { throw PlanningError.needsExpoPrebuild }
            return planReactNativeAndroid(project: project, config: config, credentials: credentials, artifactType: artifactType)
        case .nativeIOS, .unknown:
            throw PlanningError.unsupported(framework: project.framework, action: action)
        }
    }

    private static func planFlutterAndroid(
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential],
        artifactType: BuildArtifact.ArtifactType
    ) -> PlannedBuild {
        let cwd = project.url
        let pubGet = ProcessSpec(
            label: "flutter pub get",
            executable: "flutter",
            arguments: ["pub", "get"],
            workingDirectory: cwd
        )
        let isAPK = (artifactType == .apk)
        let subcommand = isAPK ? "apk" : "appbundle"
        var buildArgs = ["build", subcommand, "--release"]
        buildArgs.append(contentsOf: signingDartDefines(config: config, credentials: credentials))
        let build = ProcessSpec(
            label: "flutter build \(subcommand)",
            executable: "flutter",
            arguments: buildArgs,
            workingDirectory: cwd
        )
        let expected: PlannedArtifact = isAPK ? PlannedArtifact(
            name: "app-release.apk",
            type: .apk,
            platform: .android,
            relativePath: "build/app/outputs/flutter-apk"
        ) : PlannedArtifact(
            name: "app-release.aab",
            type: .aab,
            platform: .android,
            relativePath: "build/app/outputs/bundle/release"
        )
        return PlannedBuild(
            processSteps: [pubGet, build],
            expectedArtifacts: [expected]
        )
    }

    private static func planNativeAndroid(
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential],
        artifactType: BuildArtifact.ArtifactType
    ) -> PlannedBuild {
        let module = config.apps.android?.module ?? "app"
        let flavor = config.apps.android?.flavor
        let task = gradleTask(forFlavor: flavor, artifactType: artifactType)
        var args = [":\(module):\(task)"]
        args.append(contentsOf: signingGradleProperties(config: config, credentials: credentials))
        let gradle = ProcessSpec(
            label: "./gradlew :\(module):\(task)",
            executable: "./gradlew",
            arguments: args,
            workingDirectory: project.url
        )
        return PlannedBuild(
            processSteps: [gradle],
            expectedArtifacts: [gradleExpectedArtifact(module: module, flavor: flavor, artifactType: artifactType, androidSubdir: nil)]
        )
    }

    private static func planReactNativeAndroid(
        project: Project,
        config: ProjectConfig,
        credentials: [String: Credential],
        artifactType: BuildArtifact.ArtifactType
    ) -> PlannedBuild {
        let module = config.apps.android?.module ?? "app"
        let flavor = config.apps.android?.flavor
        let task = gradleTask(forFlavor: flavor, artifactType: artifactType)
        let pm = resolvePackageManager(project: project, config: config)
        let install = ProcessSpec(
            label: "\(pm.executable) install",
            executable: pm.executable,
            arguments: pm.installArguments,
            workingDirectory: project.url
        )
        var args = [":\(module):\(task)"]
        args.append(contentsOf: signingGradleProperties(config: config, credentials: credentials))
        let gradle = ProcessSpec(
            label: "./gradlew :\(module):\(task)",
            executable: "./gradlew",
            arguments: args,
            workingDirectory: project.url.appendingPathComponent("android")
        )
        return PlannedBuild(
            processSteps: [install, gradle],
            expectedArtifacts: [gradleExpectedArtifact(module: module, flavor: flavor, artifactType: artifactType, androidSubdir: "android")]
        )
    }

    // MARK: - Android signing

    /// Resolves the Android keystore credential referenced by the config.
    static func resolveKeystore(
        config: ProjectConfig,
        credentials: [String: Credential]
    ) -> AndroidKeystoreSecret? {
        guard let ref = config.apps.android?.signing?.keystoreRef, !ref.isEmpty,
              let credential = credentials[ref],
              case .androidKeystore(let secret) = credential.secret else {
            return nil
        }
        return secret
    }

    /// `-P` properties consumed by `app/build.gradle` via `project.findProperty(...)`.
    /// Keys: LP_KEYSTORE_FILE, LP_KEYSTORE_PASSWORD, LP_KEY_ALIAS, LP_KEY_PASSWORD.
    private static func signingGradleProperties(
        config: ProjectConfig,
        credentials: [String: Credential]
    ) -> [String] {
        guard let secret = resolveKeystore(config: config, credentials: credentials) else { return [] }
        return [
            "-PLP_KEYSTORE_FILE=\(secret.keystorePath)",
            "-PLP_KEYSTORE_PASSWORD=\(secret.keystorePassword)",
            "-PLP_KEY_ALIAS=\(secret.keyAlias)",
            "-PLP_KEY_PASSWORD=\(secret.keyPassword)"
        ]
    }

    /// Flutter forwards `--dart-define` to the runtime, but signing is read from
    /// `android/key.properties` or env vars by build.gradle. We pass the same `-P`
    /// arguments via `flutter build appbundle` — flutter passes unknown flags
    /// through to gradle.
    private static func signingDartDefines(
        config: ProjectConfig,
        credentials: [String: Credential]
    ) -> [String] {
        signingGradleProperties(config: config, credentials: credentials)
    }

    static func resolvePackageManager(project: Project, config: ProjectConfig) -> PackageManager {
        if let raw = config.project.packageManager,
           let pm = PackageManager(rawValue: raw) {
            return pm
        }
        return PackageManager.detect(at: project.url) ?? .npm
    }

    private static func gradleTask(forFlavor flavor: String?, artifactType: BuildArtifact.ArtifactType) -> String {
        let verb = (artifactType == .apk) ? "assemble" : "bundle"
        guard let flavor, !flavor.isEmpty else { return "\(verb)Release" }
        let cap = flavor.prefix(1).uppercased() + flavor.dropFirst()
        return "\(verb)\(cap)Release"
    }

    private static func gradleExpectedArtifact(
        module: String,
        flavor: String?,
        artifactType: BuildArtifact.ArtifactType,
        androidSubdir: String?
    ) -> PlannedArtifact {
        let prefix = androidSubdir.map { "\($0)/" } ?? ""
        let flavorSlug = (flavor?.isEmpty == false) ? "\(flavor!)-" : ""
        let flavorTask = (flavor?.isEmpty == false) ? "\(flavor!)Release" : "release"
        if artifactType == .apk {
            // apk path is `outputs/apk/{flavor}/{buildType}` when a flavor is set,
            // otherwise just `outputs/apk/release`.
            let apkDir = (flavor?.isEmpty == false) ? "\(flavor!)/release" : "release"
            return PlannedArtifact(
                name: "\(module)-\(flavorSlug)release.apk",
                type: .apk,
                platform: .android,
                relativePath: "\(prefix)\(module)/build/outputs/apk/\(apkDir)"
            )
        }
        return PlannedArtifact(
            name: "\(module)-\(flavorSlug)release.aab",
            type: .aab,
            platform: .android,
            relativePath: "\(prefix)\(module)/build/outputs/bundle/\(flavorTask)"
        )
    }

    private static func firstXcodeProject(in url: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        return entries.first(where: { $0.hasSuffix(".xcodeproj") })
    }

    private static func firstWorkspace(in url: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        return entries.first(where: { $0.hasSuffix(".xcworkspace") })
    }

    private static func defaultRNScheme(for project: Project) -> String? {
        let iosDir = project.url.appendingPathComponent("ios")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: iosDir.path) else { return nil }
        if let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return URL(fileURLWithPath: proj).deletingPathExtension().lastPathComponent
        }
        return nil
    }
}
