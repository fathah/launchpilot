import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppState {
    private(set) var projects: [Project] = []
    var selectedProjectId: UUID?
    var selectedSection: SidebarSection = .projects
    var lastError: String?
    var isLoading: Bool = false

    var activeSessions: [BuildSession] = []
    var recentJobs: [BuildJob] = []
    var selectedBuildId: UUID?

    var credentials: [Credential] = []
    var editingCredential: Credential?
    var addingCredentialKind: CredentialKind?

    var environmentChecks: [UUID: [EnvironmentCheck]] = [:]
    var environmentChecksInProgress: Set<UUID> = []

    private let projectStore: ProjectStore
    private let preferences: PreferencesStore
    private let buildHistory: BuildHistoryStore
    private let credentialStore: CredentialStore
    private var scopedURLs: [UUID: URL] = [:]

    init(
        projectStore: ProjectStore = ProjectStore(),
        preferences: PreferencesStore = PreferencesStore(),
        buildHistory: BuildHistoryStore = BuildHistoryStore(),
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.projectStore = projectStore
        self.preferences = preferences
        self.buildHistory = buildHistory
        self.credentialStore = credentialStore
        self.selectedSection = preferences.selectedSidebarSection
        self.selectedProjectId = preferences.selectedProjectId
    }

    var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return projects.first(where: { $0.id == id })
    }

    var hasProjects: Bool { !projects.isEmpty }

    func bootstrap() async {
        do {
            let loaded = try await projectStore.load()
            self.projects = loaded.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt })
            for project in projects {
                _ = resolveScopedURL(for: project)
            }
            if let id = selectedProjectId, !projects.contains(where: { $0.id == id }) {
                selectedProjectId = projects.first?.id
                preferences.selectedProjectId = selectedProjectId
            }
        } catch {
            self.lastError = "Failed to load projects: \(error.localizedDescription)"
        }

        do {
            let jobs = try await buildHistory.load()
            self.recentJobs = jobs.sorted(by: { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) })
        } catch {
            self.lastError = "Failed to load build history: \(error.localizedDescription)"
        }

        reloadCredentials()
    }

    func reloadCredentials() {
        credentials = credentialStore.list()
    }

    func saveCredential(_ credential: Credential, isNew: Bool, originalRef: String? = nil) throws {
        if let originalRef, originalRef != credential.ref {
            try credentialStore.rename(from: originalRef, to: credential.ref)
            try credentialStore.save(credential, isNew: false)
        } else {
            try credentialStore.save(credential, isNew: isNew)
        }
        reloadCredentials()
    }

    func refreshEnvironment(for project: Project, force: Bool = false) {
        if !force, environmentChecks[project.id] != nil { return }
        if environmentChecksInProgress.contains(project.id) { return }
        environmentChecksInProgress.insert(project.id)

        let pm = resolvedPackageManager(for: project)
        let framework = project.framework
        let projectId = project.id

        Task { [weak self] in
            let results = await EnvironmentValidator.checks(framework: framework, packageManager: pm)
            await MainActor.run {
                guard let self else { return }
                self.environmentChecks[projectId] = results
                self.environmentChecksInProgress.remove(projectId)
            }
        }
    }

    private func resolvedPackageManager(for project: Project) -> PackageManager? {
        guard project.framework == .reactNative || project.framework == .expo else { return nil }
        if let url = scopedURLs[project.id] ?? (project.bookmarkData == nil ? project.url : nil) {
            if ConfigManager.exists(at: url),
               let cfg = try? ConfigManager.read(at: url),
               let raw = cfg.project.packageManager,
               let pm = PackageManager(rawValue: raw) {
                return pm
            }
            return PackageManager.detect(at: url)
        }
        return nil
    }

    func deleteCredential(_ credential: Credential) {
        do {
            try credentialStore.delete(ref: credential.ref)
            reloadCredentials()
        } catch {
            lastError = "Failed to delete credential: \(error.localizedDescription)"
        }
    }

    func setSection(_ section: SidebarSection) {
        selectedSection = section
        preferences.selectedSidebarSection = section
    }

    func selectProject(_ project: Project) {
        selectedProjectId = project.id
        preferences.selectedProjectId = project.id
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].lastOpenedAt = Date()
            persist()
        }
    }

    func addProjectFromPicker() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select project folder"
        panel.prompt = "Add project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await addProject(at: url)
    }

    func addProject(at url: URL) async {
        isLoading = true
        defer { isLoading = false }

        if let existing = projects.first(where: { $0.path == url.path }) {
            selectProject(existing)
            return
        }

        let bookmark: Data?
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmark = nil
            lastError = "Could not create bookmark: \(error.localizedDescription)"
        }

        let detection = FrameworkDetector.detect(at: url)
        let name = url.lastPathComponent

        var project = Project(
            name: name,
            path: url.path,
            framework: detection.framework,
            bookmarkData: bookmark
        )
        project.lastOpenedAt = Date()

        projects.insert(project, at: 0)
        scopedURLs[project.id] = url
        selectedProjectId = project.id
        preferences.selectedProjectId = project.id
        persist()
    }

    func removeProject(_ project: Project) {
        if let url = scopedURLs[project.id] {
            url.stopAccessingSecurityScopedResource()
            scopedURLs.removeValue(forKey: project.id)
        }
        projects.removeAll(where: { $0.id == project.id })
        if selectedProjectId == project.id {
            selectedProjectId = projects.first?.id
            preferences.selectedProjectId = selectedProjectId
        }
        persist()
    }

    func redetectFramework(for project: Project) {
        guard let url = scopedURL(for: project) else { return }
        let result = FrameworkDetector.detect(at: url)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].framework = result.framework
            persist()
        }
    }

    func ensureConfig(for project: Project) throws -> ProjectConfig {
        guard let url = scopedURL(for: project) else {
            throw ConfigManagerError.configNotFound(project.url)
        }
        var defaults = ProjectConfig.defaults(name: project.name, framework: project.framework)
        let detected = BundleIDDetector.detect(at: url, framework: project.framework)
        if let bid = detected.iosBundleId {
            defaults.apps.ios?.bundleId = bid
            for (key, env) in defaults.environments where env.ios != nil {
                defaults.environments[key]?.ios?.bundleId = bid
            }
        }
        if let pkg = detected.androidPackage {
            defaults.apps.android?.packageName = pkg
            for (key, env) in defaults.environments where env.android != nil {
                defaults.environments[key]?.android?.packageName = pkg
            }
        }
        if usesNodePackageManager(project.framework),
           let pm = PackageManager.detect(at: url) {
            defaults.project.packageManager = pm.rawValue
        }
        let detectedEnvs = EnvironmentDetector.detect(at: url, framework: project.framework)
        if !detectedEnvs.isEmpty {
            defaults.environments = environmentDict(
                from: detectedEnvs,
                iosBundleId: defaults.apps.ios?.bundleId,
                androidPackage: defaults.apps.android?.packageName,
                iosEnabled: defaults.apps.ios != nil,
                androidEnabled: defaults.apps.android != nil
            )
        }
        return try ConfigManager.ensure(defaults, at: url)
    }

    private func environmentDict(
        from detected: [EnvironmentDetector.DetectedEnvironment],
        iosBundleId: String?,
        androidPackage: String?,
        iosEnabled: Bool,
        androidEnabled: Bool
    ) -> [String: ProjectConfig.EnvironmentConfig] {
        var dict: [String: ProjectConfig.EnvironmentConfig] = [:]
        for env in detected {
            let track: String = {
                switch env.key {
                case "production": return "production"
                case "beta": return "beta"
                case "staging": return "internal"
                default: return "internal"
                }
            }()
            let destination: String? = (env.key == "beta") ? "testflight" : nil
            dict[env.key] = ProjectConfig.EnvironmentConfig(
                displayName: env.displayName,
                ios: iosEnabled ? ProjectConfig.IOSEnvironmentOverride(
                    bundleId: iosBundleId,
                    exportMethod: "app-store",
                    destination: destination
                ) : nil,
                android: androidEnabled ? ProjectConfig.AndroidEnvironmentOverride(
                    packageName: androidPackage,
                    track: track
                ) : nil
            )
        }
        return dict
    }

    func readConfig(for project: Project) throws -> ProjectConfig {
        guard let url = scopedURL(for: project) else {
            throw ConfigManagerError.configNotFound(project.url)
        }
        return try ConfigManager.read(at: url)
    }

    func backfillBundleIDs(for project: Project) throws -> ProjectConfig {
        guard let url = scopedURL(for: project) else {
            throw ConfigManagerError.configNotFound(project.url)
        }
        var config = try ConfigManager.read(at: url)
        let detected = BundleIDDetector.detect(at: url, framework: project.framework)
        var changed = false
        if let bid = detected.iosBundleId, config.apps.ios?.bundleId?.isEmpty != false {
            config.apps.ios?.bundleId = bid
            changed = true
            for (key, env) in config.environments where env.ios != nil && env.ios?.bundleId?.isEmpty != false {
                config.environments[key]?.ios?.bundleId = bid
            }
        }
        if let pkg = detected.androidPackage, config.apps.android?.packageName?.isEmpty != false {
            config.apps.android?.packageName = pkg
            changed = true
            for (key, env) in config.environments where env.android != nil && env.android?.packageName?.isEmpty != false {
                config.environments[key]?.android?.packageName = pkg
            }
        }
        if usesNodePackageManager(project.framework),
           config.project.packageManager?.isEmpty != false,
           let pm = PackageManager.detect(at: url) {
            config.project.packageManager = pm.rawValue
            changed = true
        }
        if changed {
            try ConfigManager.write(config, to: url)
        }
        return config
    }

    private func usesNodePackageManager(_ framework: Framework) -> Bool {
        framework == .reactNative || framework == .expo
    }

    func writeConfig(_ config: ProjectConfig, for project: Project) throws {
        guard let url = scopedURL(for: project) else {
            throw ConfigManagerError.configNotFound(project.url)
        }
        try ConfigManager.write(config, to: url)
    }

    func revealInFinder(_ project: Project) {
        guard let url = scopedURL(for: project) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func startBuild(action: BuildAction, environment: String = "production", for project: Project) {
        do {
            let config = try ensureConfig(for: project)
            let credentialMap = Dictionary(uniqueKeysWithValues: credentials.map { ($0.ref, $0) })
            let session = try BuildEngine.start(
                project: project,
                action: action,
                environment: environment,
                config: config,
                credentials: credentialMap,
                onComplete: { [weak self] job in
                    self?.recordCompletion(job: job)
                }
            )
            activeSessions.append(session)
            setSection(.builds)
            selectedBuildId = session.id
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelBuild(_ session: BuildSession) {
        Task { await session.cancel() }
    }

    func session(for jobId: UUID) -> BuildSession? {
        activeSessions.first(where: { $0.id == jobId })
    }

    func project(for projectId: UUID) -> Project? {
        projects.first(where: { $0.id == projectId })
    }

    private func recordCompletion(job: BuildJob) {
        activeSessions.removeAll(where: { $0.id == job.id })
        recentJobs.insert(job, at: 0)

        // Resolve the project's artifact policy.
        let policy = artifactsPolicy(for: job.projectId)

        // Per-project retention: keep the N most-recent jobs for this project.
        let dropped = ArtifactRetention.jobsToPrune(
            in: recentJobs,
            forProjectId: job.projectId,
            keepLast: policy.keepLast
        )
        if !dropped.isEmpty {
            let droppedIds = Set(dropped.map(\.id))
            for old in dropped {
                let logURL = ArtifactRetention.logURL(projectId: old.projectId, jobId: old.id)
                try? FileManager.default.removeItem(at: logURL)
            }
            recentJobs.removeAll(where: { droppedIds.contains($0.id) })
        }

        // Hard cap across all projects.
        if recentJobs.count > 500 {
            recentJobs.removeLast(recentJobs.count - 500)
        }

        let snapshot = recentJobs
        Task { [buildHistory] in
            try? await buildHistory.save(snapshot)
        }

        // open_after_build: reveal the first artifact when configured.
        if policy.openAfterBuild,
           job.status == .succeeded,
           let firstArtifact = job.artifacts.first {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: firstArtifact.path)])
        }
    }

    private struct ArtifactsPolicy {
        let keepLast: Int
        let openAfterBuild: Bool
        static let `default` = ArtifactsPolicy(keepLast: 10, openAfterBuild: true)
    }

    private func artifactsPolicy(for projectId: UUID) -> ArtifactsPolicy {
        guard let project = projects.first(where: { $0.id == projectId }) else {
            return .default
        }
        let url = scopedURLs[project.id] ?? project.url
        guard ConfigManager.exists(at: url),
              let cfg = try? ConfigManager.read(at: url) else {
            return .default
        }
        let keep = max(1, cfg.artifacts.keepLast)
        return ArtifactsPolicy(keepLast: keep, openAfterBuild: cfg.artifacts.openAfterBuild)
    }

    private func scopedURL(for project: Project) -> URL? {
        if let url = scopedURLs[project.id] { return url }
        return resolveScopedURL(for: project)
    }

    @discardableResult
    private func resolveScopedURL(for project: Project) -> URL? {
        guard let data = project.bookmarkData else {
            let url = project.url
            scopedURLs[project.id] = url
            return url
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if url.startAccessingSecurityScopedResource() {
                scopedURLs[project.id] = url
                return url
            }
        } catch {
            lastError = "Could not resolve project folder: \(error.localizedDescription)"
        }
        return nil
    }

    private func persist() {
        let snapshot = projects
        Task { [projectStore] in
            do {
                try await projectStore.save(snapshot)
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to save projects: \(error.localizedDescription)"
                }
            }
        }
    }
}
