import Foundation

struct ProjectConfig: Codable, Hashable, Sendable {
    var version: Int
    var project: ProjectMeta
    var apps: AppsConfig
    var environments: [String: EnvironmentConfig]
    var commands: CommandsConfig
    var publishing: PublishingConfig
    var artifacts: ArtifactsConfig
    var advanced: AdvancedConfig

    struct ProjectMeta: Codable, Hashable, Sendable {
        var name: String
        var framework: String
        var root: String
    }

    struct AppsConfig: Codable, Hashable, Sendable {
        var ios: IOSAppConfig?
        var android: AndroidAppConfig?
    }

    struct IOSAppConfig: Codable, Hashable, Sendable {
        var enabled: Bool
        var bundleId: String?
        var scheme: String?
        var workspace: String?
        var configuration: String?
        var exportMethod: String?
        var teamId: String?
        var signing: IOSSigning?
        var build: IOSBuild?
    }

    struct IOSSigning: Codable, Hashable, Sendable {
        var mode: String
        var provisioningProfileName: String?
    }

    struct IOSBuild: Codable, Hashable, Sendable {
        var outputDir: String?
        var archivePath: String?
        var ipaOutputDir: String?
    }

    struct AndroidAppConfig: Codable, Hashable, Sendable {
        var enabled: Bool
        var packageName: String?
        var module: String?
        var buildType: String?
        var flavor: String?
        var artifactType: String?
        var signing: AndroidSigning?
        var build: AndroidBuild?
    }

    struct AndroidSigning: Codable, Hashable, Sendable {
        var keystoreRef: String?
    }

    struct AndroidBuild: Codable, Hashable, Sendable {
        var outputDir: String?
    }

    struct EnvironmentConfig: Codable, Hashable, Sendable {
        var displayName: String
        var ios: IOSEnvironmentOverride?
        var android: AndroidEnvironmentOverride?
    }

    struct IOSEnvironmentOverride: Codable, Hashable, Sendable {
        var bundleId: String?
        var exportMethod: String?
        var destination: String?
    }

    struct AndroidEnvironmentOverride: Codable, Hashable, Sendable {
        var packageName: String?
        var track: String?
    }

    struct CommandsConfig: Codable, Hashable, Sendable {
        var prebuild: [String]
        var postbuild: [String]
    }

    struct PublishingConfig: Codable, Hashable, Sendable {
        var apple: ApplePublishing?
        var googlePlay: GooglePlayPublishing?
    }

    struct ApplePublishing: Codable, Hashable, Sendable {
        var enabled: Bool
        var apiKeyRef: String?
        var appId: String?
    }

    struct GooglePlayPublishing: Codable, Hashable, Sendable {
        var enabled: Bool
        var serviceAccountRef: String?
        var defaultTrack: String?
    }

    struct ArtifactsConfig: Codable, Hashable, Sendable {
        var keepLast: Int
        var openAfterBuild: Bool
    }

    struct AdvancedConfig: Codable, Hashable, Sendable {
        var parallelBuilds: Bool
        var verboseLogs: Bool
    }

    static func defaults(name: String, framework: Framework) -> ProjectConfig {
        let iosEnabled = framework.supportsIOS
        let androidEnabled = framework.supportsAndroid

        let ios: IOSAppConfig? = iosEnabled ? IOSAppConfig(
            enabled: true,
            bundleId: nil,
            scheme: framework == .flutter ? "Runner" : nil,
            workspace: framework == .flutter ? "ios/Runner.xcworkspace" : nil,
            configuration: "Release",
            exportMethod: "app-store",
            teamId: nil,
            signing: IOSSigning(mode: "automatic", provisioningProfileName: nil),
            build: IOSBuild(
                outputDir: "build/ios",
                archivePath: "build/ios/archive/App.xcarchive",
                ipaOutputDir: "build/ios/ipa"
            )
        ) : nil

        let android: AndroidAppConfig? = androidEnabled ? AndroidAppConfig(
            enabled: true,
            packageName: nil,
            module: "app",
            buildType: "release",
            flavor: nil,
            artifactType: "aab",
            signing: AndroidSigning(keystoreRef: nil),
            build: AndroidBuild(outputDir: "build/android")
        ) : nil

        return ProjectConfig(
            version: 1,
            project: ProjectMeta(name: name, framework: framework.rawValue, root: "."),
            apps: AppsConfig(ios: ios, android: android),
            environments: [
                "production": EnvironmentConfig(
                    displayName: "Production",
                    ios: iosEnabled ? IOSEnvironmentOverride(bundleId: nil, exportMethod: "app-store", destination: nil) : nil,
                    android: androidEnabled ? AndroidEnvironmentOverride(packageName: nil, track: "production") : nil
                ),
                "beta": EnvironmentConfig(
                    displayName: "Beta",
                    ios: iosEnabled ? IOSEnvironmentOverride(bundleId: nil, exportMethod: "app-store", destination: "testflight") : nil,
                    android: androidEnabled ? AndroidEnvironmentOverride(packageName: nil, track: "internal") : nil
                )
            ],
            commands: CommandsConfig(prebuild: [], postbuild: []),
            publishing: PublishingConfig(
                apple: ApplePublishing(enabled: iosEnabled, apiKeyRef: nil, appId: nil),
                googlePlay: GooglePlayPublishing(enabled: androidEnabled, serviceAccountRef: nil, defaultTrack: "internal")
            ),
            artifacts: ArtifactsConfig(keepLast: 10, openAfterBuild: true),
            advanced: AdvancedConfig(parallelBuilds: true, verboseLogs: true)
        )
    }
}
