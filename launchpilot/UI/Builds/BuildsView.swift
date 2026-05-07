import SwiftUI

struct BuildsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let id = appState.selectedBuildId,
           let session = appState.session(for: id) {
            BuildDetailView(session: session)
        } else if let id = appState.selectedBuildId,
                  let job = appState.recentJobs.first(where: { $0.id == id }) {
            FinishedBuildView(job: job)
        } else {
            BuildsListView()
        }
    }
}

private struct BuildsListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !appState.activeSessions.isEmpty {
                    sectionHeader("Active")
                    VStack(spacing: 8) {
                        ForEach(appState.activeSessions) { session in
                            ActiveSessionRow(session: session)
                        }
                    }
                }

                if !appState.recentJobs.isEmpty {
                    sectionHeader("Recent")
                    VStack(spacing: 8) {
                        ForEach(appState.recentJobs) { job in
                            RecentJobRow(job: job)
                        }
                    }
                }

                if appState.activeSessions.isEmpty && appState.recentJobs.isEmpty {
                    EmptyBuildsView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Builds")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyBuildsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No builds yet")
                .font(.title3.weight(.semibold))
            Text("Open a project and start a build to see live logs and artifacts here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }
}

private struct ActiveSessionRow: View {
    @Environment(AppState.self) private var appState
    let session: BuildSession

    var body: some View {
        Button {
            appState.selectedBuildId = session.id
        } label: {
            HStack(spacing: 12) {
                StatusBadge(status: session.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(session.job.action.displayName)
                        if !session.stepLabels.isEmpty {
                            Text("·")
                            Text(session.stepLabels[min(session.currentStepIndex, session.stepLabels.count - 1)])
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RecentJobRow: View {
    @Environment(AppState.self) private var appState
    let job: BuildJob

    var body: some View {
        Button {
            appState.selectedBuildId = job.id
        } label: {
            HStack(spacing: 12) {
                StatusBadge(status: job.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.project(for: job.projectId)?.name ?? "Removed project")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(job.action.displayName)
                        Text("·")
                        Text(job.platform.displayName)
                        if let started = job.startedAt {
                            Text("·")
                            Text(started.formatted(.relative(presentation: .named)))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !job.artifacts.isEmpty {
                    Text("\(job.artifacts.count) artifact\(job.artifacts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatusBadge: View {
    let status: BuildStatus

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .font(.title3)
            .frame(width: 24)
    }

    private var symbol: String {
        switch status {
        case .queued: return "clock"
        case .running: return "circle.dotted"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var color: Color {
        switch status {
        case .queued: return .secondary
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
