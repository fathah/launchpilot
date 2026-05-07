import SwiftUI

enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case overview, environment, ios, android
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .environment: return "Environment"
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}

struct ProjectDetailView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    @State private var config: ProjectConfig?
    @State private var configError: String?
    @State private var isGenerating = false
    @State private var selectedTab: ProjectDetailTab = .overview

    private var availableTabs: [ProjectDetailTab] {
        var tabs: [ProjectDetailTab] = [.overview, .environment]
        if project.framework.supportsIOS { tabs.append(.ios) }
        if project.framework.supportsAndroid { tabs.append(.android) }
        return tabs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("", selection: $selectedTab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .overview:
                        summarySection
                        configSection
                        validationSection
                    case .environment:
                        environmentSection
                    case .ios:
                        iosTab
                    case .android:
                        androidTab
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.selectedProjectId = nil
                } label: {
                    Label("Back to Projects", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reveal in Finder") { appState.revealInFinder(project) }
                    Button("Re-detect framework") { appState.redetectFramework(for: project) }
                    Divider()
                    Button("Remove from launchpilot", role: .destructive) {
                        appState.removeProject(project)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task(id: project.id) {
            selectedTab = .overview
            loadConfig()
            appState.refreshEnvironment(for: project)
        }
    }

    @ViewBuilder
    private var iosTab: some View {
        if project.framework.supportsIOS {
            iosBuildSection
            publishingSection
            if config?.apps.ios?.enabled != true {
                Text("iOS is not enabled for this project. Enable it in launchpilot.yaml to build or publish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        } else {
            Text("This framework does not support iOS builds.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var androidTab: some View {
        if project.framework.supportsAndroid {
            androidBuildSection
            androidSigningSection
            publishingAndroidSection
            if config?.apps.android?.enabled != true {
                Text("Android is not enabled for this project. Enable it in launchpilot.yaml to build or publish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        } else {
            Text("This framework does not support Android builds.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var iosBuildSection: some View {
        SectionCard(title: "Build iOS") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    appState.startBuild(action: .buildIOSIPA, for: project)
                } label: {
                    Label("Archive iOS", systemImage: "applelogo")
                }
                .disabled(config?.apps.ios?.enabled != true)
                .buttonStyle(.borderedProminent)
                Text("Builds run on your Mac using the same tools you'd use in Terminal. Logs and artifacts are saved to ~/Library/Application Support/launchpilot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var androidBuildSection: some View {
        SectionCard(title: "Build Android") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    appState.startBuild(action: .buildAndroidAAB, for: project)
                } label: {
                    Label("Build Android AAB", systemImage: "smartphone")
                }
                .disabled(config?.apps.android?.enabled != true)
                .buttonStyle(.borderedProminent)
                Text("Builds run on your Mac using the same tools you'd use in Terminal. Logs and artifacts are saved to ~/Library/Application Support/launchpilot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FrameworkBadge(framework: project.framework)
                if let cfg = config {
                    Text("\(cfg.environments.count) environments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(project.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var summarySection: some View {
        SectionCard(title: "Overview") {
            HStack(spacing: 32) {
                StatTile(label: "Framework", value: project.framework.displayName)
                StatTile(
                    label: "iOS",
                    value: config?.apps.ios?.enabled == true ? "Enabled" : "Off"
                )
                StatTile(
                    label: "Android",
                    value: config?.apps.android?.enabled == true ? "Enabled" : "Off"
                )
                StatTile(
                    label: "Config",
                    value: config != nil ? "Loaded" : (configError != nil ? "Error" : "Not created")
                )
            }
        }
    }

    @ViewBuilder
    private var configSection: some View {
        SectionCard(title: AppConstants.configFileName) {
            if let cfg = config {
                VStack(alignment: .leading, spacing: 8) {
                    KeyValueRow(label: "Project name", value: cfg.project.name)
                    KeyValueRow(label: "Framework", value: cfg.project.framework)
                    if let bundle = cfg.apps.ios?.bundleId, !bundle.isEmpty {
                        KeyValueRow(label: "iOS bundle ID", value: bundle)
                    }
                    if let pkg = cfg.apps.android?.packageName, !pkg.isEmpty {
                        KeyValueRow(label: "Android package", value: pkg)
                    }
                    if usesNodePM {
                        packageManagerPicker(current: cfg.project.packageManager)
                    }
                    if !cfg.environments.isEmpty {
                        KeyValueRow(
                            label: "Environments",
                            value: cfg.environments.keys.sorted().joined(separator: ", ")
                        )
                    }
                }
            } else if let err = configError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No \(AppConstants.configFileName) yet for this project.")
                        .foregroundStyle(.secondary)
                    Button {
                        generateConfig()
                    } label: {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Create launchpilot.yaml", systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(isGenerating)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        let checks = appState.environmentChecks[project.id]
        let inProgress = appState.environmentChecksInProgress.contains(project.id)
        SectionCard(title: "Environment") {
            VStack(alignment: .leading, spacing: 10) {
                if let checks {
                    ForEach(checks) { check in
                        EnvironmentRow(check: check)
                    }
                    HStack {
                        Spacer()
                        if inProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                appState.refreshEnvironment(for: project, force: true)
                            } label: {
                                Label("Re-run checks", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else if inProgress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running pre-flight checks…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        appState.refreshEnvironment(for: project, force: true)
                    } label: {
                        Label("Run pre-flight checks", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let cfg = config,
           let adapter = FrameworkDetector.adapter(for: project.framework) {
            let issues = adapter.validate(project: project, config: cfg)
            if !issues.isEmpty {
                SectionCard(title: "Pre-build checks") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(issues) { issue in
                            ValidationRow(issue: issue)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var androidSigningSection: some View {
        if project.framework.supportsAndroid, config?.apps.android?.enabled == true {
            SectionCard(title: "Android signing") {
                VStack(alignment: .leading, spacing: 12) {
                    keystoreCredentialPicker
                    if hasKeystoreSelected {
                        AndroidSigningSnippet()
                    } else {
                        Text("Select a keystore credential to sign release AAB/APK builds. launchpilot passes the keystore details to Gradle as `-P` properties — your `app/build.gradle` reads them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var keystoreCredentials: [Credential] {
        appState.credentials.filter { $0.kind == .androidKeystore }
    }

    private var selectedKeystoreRef: String? {
        config?.apps.android?.signing?.keystoreRef
    }

    private var hasKeystoreSelected: Bool {
        guard let ref = selectedKeystoreRef, !ref.isEmpty else { return false }
        return keystoreCredentials.contains(where: { $0.ref == ref })
    }

    @ViewBuilder
    private var keystoreCredentialPicker: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Release keystore")
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            if keystoreCredentials.isEmpty {
                HStack(spacing: 8) {
                    Text("No keystores saved")
                        .foregroundStyle(.secondary)
                    Button("Open Credentials") {
                        appState.setSection(.credentials)
                    }
                    .buttonStyle(.link)
                }
            } else {
                Picker("", selection: Binding<String>(
                    get: { selectedKeystoreRef ?? "" },
                    set: { setKeystoreRef($0.isEmpty ? nil : $0) }
                )) {
                    Text("None").tag("")
                    ForEach(keystoreCredentials) { credential in
                        Text("\(credential.displayName) — \(credential.ref)")
                            .tag(credential.ref)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 360)
            }
            Spacer()
        }
    }

    private func setKeystoreRef(_ ref: String?) {
        guard var cfg = config else { return }
        if cfg.apps.android == nil { return }
        if cfg.apps.android?.signing == nil {
            cfg.apps.android?.signing = ProjectConfig.AndroidSigning(keystoreRef: ref)
        } else {
            cfg.apps.android?.signing?.keystoreRef = ref
        }
        do {
            try appState.writeConfig(cfg, for: project)
            config = cfg
        } catch {
            configError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var publishingSection: some View {
        if project.framework.supportsIOS, config?.apps.ios?.enabled == true {
            SectionCard(title: "Publish iOS") {
                VStack(alignment: .leading, spacing: 12) {
                    appleCredentialPicker
                    HStack(spacing: 12) {
                        Button {
                            appState.startBuild(action: .publishTestFlight, for: project)
                        } label: {
                            Label("Archive + Upload to TestFlight", systemImage: "paperplane.fill")
                        }
                        .disabled(!canUploadToApple)
                        .buttonStyle(.borderedProminent)

                        Button {
                            appState.startBuild(action: .publishAppStore, for: project)
                        } label: {
                            Label("Archive + Upload to App Store", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(!canUploadToApple)
                    }
                    Text("Runs the iOS archive + export, then `xcrun altool --upload-app` with the selected key. The .p8 is staged in a temp dir and removed when the build finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appleCredentials: [Credential] {
        appState.credentials.filter { $0.kind == .appleAPIKey }
    }

    private var selectedAppleRef: String? {
        config?.publishing.apple?.apiKeyRef
    }

    private var canUploadToApple: Bool {
        guard let ref = selectedAppleRef, !ref.isEmpty else { return false }
        return appleCredentials.contains(where: { $0.ref == ref })
    }

    @ViewBuilder
    private var appleCredentialPicker: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("App Store Connect key")
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            if appleCredentials.isEmpty {
                HStack(spacing: 8) {
                    Text("No Apple keys saved")
                        .foregroundStyle(.secondary)
                    Button("Open Credentials") {
                        appState.setSection(.credentials)
                    }
                    .buttonStyle(.link)
                }
            } else {
                Picker("", selection: Binding<String>(
                    get: { selectedAppleRef ?? "" },
                    set: { setAppleApiKeyRef($0.isEmpty ? nil : $0) }
                )) {
                    Text("None").tag("")
                    ForEach(appleCredentials) { credential in
                        Text("\(credential.displayName) — \(credential.ref)")
                            .tag(credential.ref)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 360)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var publishingAndroidSection: some View {
        if project.framework.supportsAndroid, config?.apps.android?.enabled == true {
            SectionCard(title: "Publish Android") {
                VStack(alignment: .leading, spacing: 12) {
                    googlePlayCredentialPicker
                    googlePlayTrackPicker
                    HStack(spacing: 12) {
                        Button {
                            appState.startBuild(action: .publishGooglePlay, for: project)
                        } label: {
                            Label("Build + Upload to Google Play", systemImage: "paperplane.fill")
                        }
                        .disabled(!canUploadToGooglePlay)
                        .buttonStyle(.borderedProminent)
                    }
                    Text("Builds the release AAB, then uploads it to the chosen Play Console track via the Google Play Developer API. The bundle is created as a draft release — promote it from Play Console.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var googlePlayCredentials: [Credential] {
        appState.credentials.filter { $0.kind == .googlePlayServiceAccount }
    }

    private var selectedGooglePlayRef: String? {
        config?.publishing.googlePlay?.serviceAccountRef
    }

    private var canUploadToGooglePlay: Bool {
        guard let ref = selectedGooglePlayRef, !ref.isEmpty else { return false }
        guard googlePlayCredentials.contains(where: { $0.ref == ref }) else { return false }
        return !(config?.apps.android?.packageName?.isEmpty ?? true)
    }

    @ViewBuilder
    private var googlePlayCredentialPicker: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Service account")
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            if googlePlayCredentials.isEmpty {
                HStack(spacing: 8) {
                    Text("No service accounts saved")
                        .foregroundStyle(.secondary)
                    Button("Open Credentials") {
                        appState.setSection(.credentials)
                    }
                    .buttonStyle(.link)
                }
            } else {
                Picker("", selection: Binding<String>(
                    get: { selectedGooglePlayRef ?? "" },
                    set: { setGooglePlayRef($0.isEmpty ? nil : $0) }
                )) {
                    Text("None").tag("")
                    ForEach(googlePlayCredentials) { credential in
                        Text("\(credential.displayName) — \(credential.ref)")
                            .tag(credential.ref)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 360)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var googlePlayTrackPicker: some View {
        let tracks = ["internal", "alpha", "beta", "production"]
        let current = config?.publishing.googlePlay?.defaultTrack ?? "internal"
        HStack(alignment: .firstTextBaseline) {
            Text("Default track")
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            Picker("", selection: Binding<String>(
                get: { current },
                set: { setGooglePlayTrack($0) }
            )) {
                ForEach(tracks, id: \.self) { track in
                    Text(track.capitalized).tag(track)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            Spacer()
        }
    }

    private func setGooglePlayRef(_ ref: String?) {
        guard var cfg = config else { return }
        if cfg.publishing.googlePlay == nil {
            cfg.publishing.googlePlay = ProjectConfig.GooglePlayPublishing(
                enabled: true,
                serviceAccountRef: ref,
                defaultTrack: "internal"
            )
        } else {
            cfg.publishing.googlePlay?.serviceAccountRef = ref
            cfg.publishing.googlePlay?.enabled = true
        }
        do {
            try appState.writeConfig(cfg, for: project)
            config = cfg
        } catch {
            configError = error.localizedDescription
        }
    }

    private func setGooglePlayTrack(_ track: String) {
        guard var cfg = config else { return }
        if cfg.publishing.googlePlay == nil {
            cfg.publishing.googlePlay = ProjectConfig.GooglePlayPublishing(
                enabled: true,
                serviceAccountRef: nil,
                defaultTrack: track
            )
        } else {
            cfg.publishing.googlePlay?.defaultTrack = track
        }
        do {
            try appState.writeConfig(cfg, for: project)
            config = cfg
        } catch {
            configError = error.localizedDescription
        }
    }

    private func setAppleApiKeyRef(_ ref: String?) {
        guard var cfg = config else { return }
        if cfg.publishing.apple == nil {
            cfg.publishing.apple = ProjectConfig.ApplePublishing(enabled: true, apiKeyRef: ref, appId: nil)
        } else {
            cfg.publishing.apple?.apiKeyRef = ref
            cfg.publishing.apple?.enabled = true
        }
        do {
            try appState.writeConfig(cfg, for: project)
            config = cfg
        } catch {
            configError = error.localizedDescription
        }
    }

    private var usesNodePM: Bool {
        project.framework == .reactNative || project.framework == .expo
    }

    @ViewBuilder
    private func packageManagerPicker(current: String?) -> some View {
        let resolved: PackageManager = {
            if let raw = current, let pm = PackageManager(rawValue: raw) { return pm }
            return PackageManager.detect(at: project.url) ?? .npm
        }()
        let detectedNote: String? = {
            if current == nil, let pm = PackageManager.detect(at: project.url) {
                return "Detected from lockfile: \(pm.displayName)"
            }
            return nil
        }()

        HStack(alignment: .firstTextBaseline) {
            Text("Package manager")
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            Picker("", selection: Binding(
                get: { resolved },
                set: { setPackageManager($0) }
            )) {
                ForEach(PackageManager.allCases) { pm in
                    Text(pm.displayName).tag(pm)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
            if let note = detectedNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func setPackageManager(_ pm: PackageManager) {
        guard var cfg = config else { return }
        cfg.project.packageManager = pm.rawValue
        do {
            try appState.writeConfig(cfg, for: project)
            config = cfg
        } catch {
            configError = error.localizedDescription
        }
    }

    private func loadConfig() {
        configError = nil
        if ConfigManager.exists(at: project.url) {
            do {
                config = try appState.backfillBundleIDs(for: project)
            } catch {
                config = nil
                configError = error.localizedDescription
            }
        } else {
            config = nil
        }
    }

    private func generateConfig() {
        isGenerating = true
        defer { isGenerating = false }
        do {
            config = try appState.ensureConfig(for: project)
        } catch {
            configError = error.localizedDescription
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
        }
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct ValidationRow: View {
    let issue: ValidationIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.callout.weight(.medium))
                if let detail = issue.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let hint = issue.fixHint {
                    Text(hint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var symbol: String {
        switch issue.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch issue.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
