import Foundation

nonisolated enum AppConstants {
    static let appName = "launchpilot"
    static let configFileName = "launchpilot.yaml"
    static let configBackupExtension = "yaml.bak"
    static let bundleIdentifier = "com.fathaaah.launchpilot"

    static var applicationSupportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var projectsStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("projects.json")
    }

    static var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    static var artifactsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("artifacts", isDirectory: true)
    }
}
