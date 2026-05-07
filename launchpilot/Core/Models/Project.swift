import Foundation

struct Project: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var framework: Framework
    var bookmarkData: Data?
    var lastOpenedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        framework: Framework = .unknown,
        bookmarkData: Data? = nil,
        lastOpenedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.framework = framework
        self.bookmarkData = bookmarkData
        self.lastOpenedAt = lastOpenedAt
        self.createdAt = createdAt
    }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}
