import Foundation

nonisolated struct PreferencesStore {
    private enum Key {
        static let selectedProjectId = "selectedProjectId"
        static let selectedSidebarSection = "selectedSidebarSection"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedProjectId: UUID? {
        get {
            guard let str = defaults.string(forKey: Key.selectedProjectId) else { return nil }
            return UUID(uuidString: str)
        }
        nonmutating set {
            defaults.set(newValue?.uuidString, forKey: Key.selectedProjectId)
        }
    }

    var selectedSidebarSection: SidebarSection {
        get {
            guard let raw = defaults.string(forKey: Key.selectedSidebarSection),
                  let section = SidebarSection(rawValue: raw) else {
                return .projects
            }
            return section
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.selectedSidebarSection)
        }
    }
}
