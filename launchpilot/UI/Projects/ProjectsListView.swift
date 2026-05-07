import SwiftUI

struct ProjectsListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(appState.projects) { project in
                    Button {
                        appState.selectProject(project)
                    } label: {
                        ProjectCardView(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Reveal in Finder") { appState.revealInFinder(project) }
                        Button("Re-detect framework") { appState.redetectFramework(for: project) }
                        Divider()
                        Button("Remove from launchpilot", role: .destructive) {
                            appState.removeProject(project)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.addProjectFromPicker() }
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }
        }
    }
}

struct ProjectCardView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                    .font(.title3)
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                FrameworkBadge(framework: project.framework)
            }

            Text(project.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            HStack {
                Text("Last opened \(project.lastOpenedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(16)
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }
}

struct FrameworkBadge: View {
    let framework: Framework

    var body: some View {
        Text(framework.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(badgeColor.opacity(0.15))
            )
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch framework {
        case .flutter: return .blue
        case .expo: return .indigo
        case .reactNative: return .cyan
        case .nativeIOS: return .gray
        case .nativeAndroid: return .green
        case .unknown: return .secondary
        }
    }
}
