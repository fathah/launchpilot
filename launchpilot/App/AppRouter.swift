import Foundation

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case projects
    case builds
    case releases
    case credentials
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .builds: return "Builds"
        case .releases: return "Releases"
        case .credentials: return "Credentials"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .projects: return "folder"
        case .builds: return "hammer"
        case .releases: return "shippingbox"
        case .credentials: return "key"
        case .settings: return "gearshape"
        }
    }
}
