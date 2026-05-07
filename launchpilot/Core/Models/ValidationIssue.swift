import Foundation

struct ValidationIssue: Identifiable, Hashable, Sendable {
    enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let severity: Severity
    let title: String
    let detail: String?
    let fixHint: String?

    init(severity: Severity, title: String, detail: String? = nil, fixHint: String? = nil) {
        self.id = UUID()
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fixHint = fixHint
    }
}
