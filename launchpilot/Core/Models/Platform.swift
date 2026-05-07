import Foundation

enum Platform: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case iOS = "ios"
    case android = "android"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOS: return "iOS"
        case .android: return "Android"
        }
    }

    var symbolName: String {
        switch self {
        case .iOS: return "applelogo"
        case .android: return "smartphone"
        }
    }
}
