import Foundation

actor ProjectStore {
    private let fileURL: URL

    init(fileURL: URL = AppConstants.projectsStoreURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [Project] {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Project].self, from: data)
    }

    func save(_ projects: [Project]) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
