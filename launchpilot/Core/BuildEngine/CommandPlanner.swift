import Foundation

struct PlannedBuild: Sendable {
    let steps: [ProcessSpec]
    let expectedArtifacts: [PlannedArtifact]
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
    static func plan(action: BuildAction, project: Project, config: ProjectConfig) throws -> PlannedBuild {
        switch action {
        case .buildIOSIPA, .archiveOnly where project.framework.supportsIOS:
            return try planIOS(project: project, config: config)
        case .buildAndroidAAB, .archiveOnly:
            return try planAndroid(project: project, config: config)
        case .publishTestFlight, .publishAppStore, .publishGooglePlay:
            throw PlanningError.unsupported(framework: project.framework, action: action)
        }
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
            steps: [pubGet, buildIPA],
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
        return PlannedBuild(
            steps: [archive],
            expectedArtifacts: [
                PlannedArtifact(
                    name: URL(fileURLWithPath: archiveRel).lastPathComponent,
                    type: .xcarchive,
                    platform: .iOS,
                    relativePath: URL(fileURLWithPath: archiveRel).deletingLastPathComponent().relativePath
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
        let iosDir = project.url.appendingPathComponent("ios")

        let install = ProcessSpec(
            label: "npm install",
            executable: "npm",
            arguments: ["install"],
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

        return PlannedBuild(
            steps: [install, pod, archive],
            expectedArtifacts: [
                PlannedArtifact(
                    name: URL(fileURLWithPath: archiveRel).lastPathComponent,
                    type: .xcarchive,
                    platform: .iOS,
                    relativePath: URL(fileURLWithPath: archiveRel).deletingLastPathComponent().relativePath
                )
            ]
        )
    }

    // MARK: - Android

    private static func planAndroid(project: Project, config: ProjectConfig) throws -> PlannedBuild {
        guard config.apps.android?.enabled == true else {
            throw PlanningError.missing("Android is not enabled in launchpilot.yaml")
        }
        switch project.framework {
        case .flutter:
            return planFlutterAndroid(project: project, config: config)
        case .reactNative:
            return planReactNativeAndroid(project: project, config: config)
        case .nativeAndroid:
            return planNativeAndroid(project: project, config: config)
        case .expo:
            let androidDir = project.url.appendingPathComponent("android")
            guard DetectionFS.isDirectory(androidDir) else { throw PlanningError.needsExpoPrebuild }
            return planReactNativeAndroid(project: project, config: config)
        case .nativeIOS, .unknown:
            throw PlanningError.unsupported(framework: project.framework, action: .buildAndroidAAB)
        }
    }

    private static func planFlutterAndroid(project: Project, config: ProjectConfig) -> PlannedBuild {
        let cwd = project.url
        let pubGet = ProcessSpec(
            label: "flutter pub get",
            executable: "flutter",
            arguments: ["pub", "get"],
            workingDirectory: cwd
        )
        let appbundle = ProcessSpec(
            label: "flutter build appbundle",
            executable: "flutter",
            arguments: ["build", "appbundle", "--release"],
            workingDirectory: cwd
        )
        return PlannedBuild(
            steps: [pubGet, appbundle],
            expectedArtifacts: [
                PlannedArtifact(
                    name: "app-release.aab",
                    type: .aab,
                    platform: .android,
                    relativePath: "build/app/outputs/bundle/release"
                )
            ]
        )
    }

    private static func planNativeAndroid(project: Project, config: ProjectConfig) -> PlannedBuild {
        let module = config.apps.android?.module ?? "app"
        let task = bundleTask(forFlavor: config.apps.android?.flavor)
        let gradle = ProcessSpec(
            label: "./gradlew :\(module):\(task)",
            executable: "./gradlew",
            arguments: [":\(module):\(task)"],
            workingDirectory: project.url
        )
        return PlannedBuild(
            steps: [gradle],
            expectedArtifacts: [
                PlannedArtifact(
                    name: "\(module)-release.aab",
                    type: .aab,
                    platform: .android,
                    relativePath: "\(module)/build/outputs/bundle/release"
                )
            ]
        )
    }

    private static func planReactNativeAndroid(project: Project, config: ProjectConfig) -> PlannedBuild {
        let module = config.apps.android?.module ?? "app"
        let task = bundleTask(forFlavor: config.apps.android?.flavor)
        let install = ProcessSpec(
            label: "npm install",
            executable: "npm",
            arguments: ["install"],
            workingDirectory: project.url
        )
        let gradle = ProcessSpec(
            label: "./gradlew :\(module):\(task)",
            executable: "./gradlew",
            arguments: [":\(module):\(task)"],
            workingDirectory: project.url.appendingPathComponent("android")
        )
        return PlannedBuild(
            steps: [install, gradle],
            expectedArtifacts: [
                PlannedArtifact(
                    name: "\(module)-release.aab",
                    type: .aab,
                    platform: .android,
                    relativePath: "android/\(module)/build/outputs/bundle/release"
                )
            ]
        )
    }

    private static func bundleTask(forFlavor flavor: String?) -> String {
        guard let flavor, !flavor.isEmpty else { return "bundleRelease" }
        let cap = flavor.prefix(1).uppercased() + flavor.dropFirst()
        return "bundle\(cap)Release"
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
