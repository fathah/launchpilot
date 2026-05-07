import Foundation
import Observation

@MainActor
@Observable
final class BuildSession: Identifiable {
    let job: BuildJob
    let project: Project

    var status: BuildStatus
    var lines: [LogLine] = []
    var currentStepIndex: Int = 0
    var stepLabels: [String] = []
    var stepStatuses: [BuildStatus] = []
    var startedAt: Date?
    var completedAt: Date?
    var artifacts: [BuildArtifact] = []
    var failureReason: String?
    var resolvedCommandLines: [String] = []
    var logFileURL: URL?

    let cancellation = ProcessCancellation()

    var id: UUID { job.id }

    init(job: BuildJob, project: Project, stepLabels: [String]) {
        self.job = job
        self.project = project
        self.status = .queued
        self.stepLabels = stepLabels
        self.stepStatuses = Array(repeating: .queued, count: stepLabels.count)
    }

    func append(_ line: LogLine) {
        lines.append(line)
        if lines.count > 5000 {
            lines.removeFirst(lines.count - 5000)
        }
    }

    func cancel() async {
        await cancellation.cancel()
    }

    func snapshotJob() -> BuildJob {
        var snapshot = job
        snapshot.status = status
        snapshot.startedAt = startedAt
        snapshot.completedAt = completedAt
        snapshot.artifacts = artifacts
        return snapshot
    }
}
