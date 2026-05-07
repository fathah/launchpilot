import Foundation

enum ConfigManagerError: Error, LocalizedError {
    case configNotFound(URL)
    case writeFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .configNotFound(let url): return "No \(AppConstants.configFileName) at \(url.path)"
        case .writeFailed(let url, let err): return "Failed to write \(url.lastPathComponent): \(err.localizedDescription)"
        }
    }
}

struct ConfigManager {
    static let header: String = """
    # \(AppConstants.configFileName)
    # Managed by launchpilot. Safe to commit. Secrets must NOT be stored here.

    """

    static func configURL(for projectURL: URL) -> URL {
        projectURL.appendingPathComponent(AppConstants.configFileName)
    }

    static func exists(at projectURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: configURL(for: projectURL).path)
    }

    static func read(at projectURL: URL) throws -> ProjectConfig {
        let url = configURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigManagerError.configNotFound(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try YAMLCodec.decode(ProjectConfig.self, from: text)
    }

    static func write(_ config: ProjectConfig, to projectURL: URL) throws {
        let url = configURL(for: projectURL)
        try backupIfNeeded(at: url)
        let body = try YAMLCodec.encode(config)
        let output = header + body
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigManagerError.writeFailed(url, error)
        }
    }

    static func ensure(_ config: ProjectConfig, at projectURL: URL) throws -> ProjectConfig {
        if exists(at: projectURL) {
            return try read(at: projectURL)
        }
        try write(config, to: projectURL)
        return config
    }

    private static func backupIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.deletingPathExtension().appendingPathExtension(AppConstants.configBackupExtension)
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        try FileManager.default.copyItem(at: url, to: backup)
    }
}
