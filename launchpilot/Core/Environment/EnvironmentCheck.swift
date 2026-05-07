import Foundation

struct EnvironmentCheck: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case ok(version: String?)
        case warning(message: String)
        case missing
        case error(String)
    }

    enum Severity: String, Hashable, Sendable {
        case required   // build will fail without it
        case recommended // build may work, but expected for the workflow
        case optional    // nice-to-have
    }

    let id: String
    let displayName: String
    let detail: String?
    let severity: Severity
    let status: Status
    let installHint: String?

    var isSatisfied: Bool {
        if case .ok = status { return true }
        return false
    }

    var iconName: String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .missing: return "xmark.octagon.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
