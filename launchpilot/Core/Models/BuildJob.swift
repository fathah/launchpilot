import Foundation

enum BuildAction: String, Codable, CaseIterable, Sendable {
    case archiveOnly = "archive_only"
    case buildIOSIPA = "build_ios_ipa"
    case buildAndroidAAB = "build_android_aab"
    case publishTestFlight = "publish_testflight"
    case publishAppStore = "publish_app_store"
    case publishGooglePlay = "publish_google_play"

    var displayName: String {
        switch self {
        case .archiveOnly: return "Archive only"
        case .buildIOSIPA: return "Build iOS IPA"
        case .buildAndroidAAB: return "Build Android AAB"
        case .publishTestFlight: return "Publish to TestFlight"
        case .publishAppStore: return "Publish to App Store"
        case .publishGooglePlay: return "Publish to Google Play"
        }
    }
}

enum BuildStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

struct BuildCommand: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let label: String
    let executable: String
    let arguments: [String]
    var exitCode: Int32?
    var startedAt: Date?
    var completedAt: Date?

    init(label: String, executable: String, arguments: [String]) {
        self.id = UUID()
        self.label = label
        self.executable = executable
        self.arguments = arguments
    }
}

struct BuildArtifact: Identifiable, Hashable, Codable, Sendable {
    enum ArtifactType: String, Codable, Sendable {
        case xcarchive
        case ipa
        case aab
        case apk
        case logs
    }

    let id: UUID
    var name: String
    var type: ArtifactType
    var platform: Platform
    var path: String
    var sizeBytes: Int64?
    var createdAt: Date
    var buildId: UUID
    var environment: String?

    init(name: String, type: ArtifactType, platform: Platform, path: String, buildId: UUID, environment: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.platform = platform
        self.path = path
        self.createdAt = Date()
        self.buildId = buildId
        self.environment = environment
    }
}

struct BuildJob: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let projectId: UUID
    let platform: Platform
    let environment: String
    let action: BuildAction
    var status: BuildStatus
    var startedAt: Date?
    var completedAt: Date?
    var commands: [BuildCommand]
    var artifacts: [BuildArtifact]
    var failureReason: String?
    var failedStepLabel: String?

    init(
        projectId: UUID,
        platform: Platform,
        environment: String,
        action: BuildAction
    ) {
        self.id = UUID()
        self.projectId = projectId
        self.platform = platform
        self.environment = environment
        self.action = action
        self.status = .queued
        self.commands = []
        self.artifacts = []
    }
}
