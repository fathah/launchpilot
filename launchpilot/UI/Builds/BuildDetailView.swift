import SwiftUI

struct BuildDetailView: View {
    @Environment(AppState.self) private var appState
    let session: BuildSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepsBar
            if session.status == .failed {
                FailureBanner(
                    failureReason: session.failureReason,
                    failedStepLabel: failedStepLabel,
                    diagnosis: ErrorDiagnoser.diagnose(failureReason: session.failureReason, lines: session.lines)
                )
            }
            Divider()
            LogConsoleView(lines: session.lines, autoScroll: session.status == .running)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("\(session.project.name) — \(session.job.action.displayName)")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.selectedBuildId = nil
                } label: {
                    Label("Builds", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if session.status == .running {
                    Button(role: .destructive) {
                        appState.cancelBuild(session)
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        copyLogToClipboard()
                    } label: {
                        Label("Copy log", systemImage: "doc.on.doc")
                    }
                    if let url = session.logFileURL {
                        Button {
                            appState.revealInFinder(path: url.path)
                        } label: {
                            Label("Reveal log", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }
        }
    }

    private var failedStepLabel: String? {
        guard session.stepStatuses.indices.contains(session.currentStepIndex),
              session.stepStatuses[session.currentStepIndex] == .failed,
              session.stepLabels.indices.contains(session.currentStepIndex) else { return nil }
        return session.stepLabels[session.currentStepIndex]
    }

    private func copyLogToClipboard() {
        let text = session.lines.map { line in
            line.stream == .stderr ? "[stderr] \(line.text)" : line.text
        }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var header: some View {
        HStack(spacing: 16) {
            StatusBadge(status: session.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.project.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(session.job.action.displayName)
                    Text("·")
                    Text(session.job.platform.displayName)
                    if let started = session.startedAt {
                        Text("·")
                        Text("started \(started.formatted(date: .omitted, time: .shortened))")
                    }
                    if let duration = duration {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if session.status == .succeeded && !session.artifacts.isEmpty {
                ArtifactsSummary(artifacts: session.artifacts)
            }
        }
        .padding(16)
    }

    private var duration: String? {
        guard let started = session.startedAt else { return nil }
        let end = session.completedAt ?? Date()
        let interval = end.timeIntervalSince(started)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval)
    }

    private var stepsBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(session.stepLabels.enumerated()), id: \.offset) { index, label in
                StepChip(
                    label: label,
                    status: session.stepStatuses[safe: index] ?? .queued,
                    isCurrent: index == session.currentStepIndex && session.status == .running
                )
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct StepChip: View {
    let label: String
    let status: BuildStatus
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var symbol: String {
        switch status {
        case .queued: return "circle"
        case .running: return "circle.dotted"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
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

struct LogConsoleView: View {
    let lines: [LogLine]
    let autoScroll: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(line.stream == .stderr ? Color.red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id(-1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { _, newCount in
                guard autoScroll, newCount > 0 else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo(-1, anchor: .bottom)
                }
            }
        }
    }
}

private struct ArtifactsSummary: View {
    @Environment(AppState.self) private var appState
    let artifacts: [BuildArtifact]

    var body: some View {
        Menu {
            ForEach(artifacts) { artifact in
                Button {
                    appState.revealInFinder(path: artifact.path)
                } label: {
                    Label(artifact.name, systemImage: "shippingbox.fill")
                }
            }
        } label: {
            Label("\(artifacts.count) artifact\(artifacts.count == 1 ? "" : "s")", systemImage: "shippingbox.fill")
        }
        .menuStyle(.borderlessButton)
    }
}

struct FinishedBuildView: View {
    @Environment(AppState.self) private var appState
    let job: BuildJob

    @State private var logText: String = ""
    @State private var loadFailed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                StatusBadge(status: job.status)
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.project(for: job.projectId)?.name ?? "Removed project")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(job.action.displayName)
                        Text("·")
                        Text(job.platform.displayName)
                        if let started = job.startedAt {
                            Text("·")
                            Text(started.formatted())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !job.artifacts.isEmpty {
                    Menu {
                        ForEach(job.artifacts) { artifact in
                            Button(artifact.name) {
                                appState.revealInFinder(path: artifact.path)
                            }
                        }
                    } label: {
                        Label("Artifacts", systemImage: "shippingbox.fill")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(16)
            if job.status == .failed {
                Divider()
                FailureBanner(
                    failureReason: job.failureReason,
                    failedStepLabel: job.failedStepLabel,
                    diagnosis: ErrorDiagnoser.diagnose(failureReason: job.failureReason, logText: logText)
                )
            }
            Divider()
            ScrollView {
                Text(logText.isEmpty ? (loadFailed ? "Could not load log file." : "Loading…") : logText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(appState.project(for: job.projectId)?.name ?? "Build")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.selectedBuildId = nil
                } label: {
                    Label("Builds", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyLogToClipboard()
                } label: {
                    Label("Copy log", systemImage: "doc.on.doc")
                }
                .disabled(logText.isEmpty)
            }
        }
        .task(id: job.id) {
            loadLog()
        }
    }

    private func loadLog() {
        let url = AppConstants.logsDirectory
            .appendingPathComponent(job.projectId.uuidString, isDirectory: true)
            .appendingPathComponent("\(job.id.uuidString).log")
        do {
            logText = try String(contentsOf: url, encoding: .utf8)
            loadFailed = false
        } catch {
            logText = ""
            loadFailed = true
        }
    }

    private func copyLogToClipboard() {
        guard !logText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }
}

struct FailureBanner: View {
    let failureReason: String?
    let failedStepLabel: String?
    let diagnosis: Diagnosis?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosis?.title ?? primaryHeadline)
                        .font(.headline)
                    if let reason = failureReason {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }

            if let diagnosis {
                VStack(alignment: .leading, spacing: 6) {
                    Text(diagnosis.explanation)
                        .font(.callout)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text(diagnosis.suggestion)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
    }

    private var primaryHeadline: String {
        if let failedStepLabel {
            return "Step \"\(failedStepLabel)\" failed"
        }
        return "Build failed"
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
