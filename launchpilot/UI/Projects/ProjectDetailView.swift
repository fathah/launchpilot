import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    @State private var config: ProjectConfig?
    @State private var configError: String?
    @State private var isGenerating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                summarySection

                configSection

                validationSection

                actionsSection
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
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
            loadConfig()
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

    private var actionsSection: some View {
        SectionCard(title: "Build") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        appState.startBuild(action: .buildIOSIPA, for: project)
                    } label: {
                        Label("Archive iOS", systemImage: "applelogo")
                    }
                    .disabled(!project.framework.supportsIOS || config?.apps.ios?.enabled != true)
                    .buttonStyle(.borderedProminent)

                    Button {
                        appState.startBuild(action: .buildAndroidAAB, for: project)
                    } label: {
                        Label("Build Android AAB", systemImage: "smartphone")
                    }
                    .disabled(!project.framework.supportsAndroid || config?.apps.android?.enabled != true)
                    .buttonStyle(.bordered)
                }
                Text("Builds run on your Mac using the same tools you'd use in Terminal. Logs and artifacts are saved to ~/Library/Application Support/launchpilot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
