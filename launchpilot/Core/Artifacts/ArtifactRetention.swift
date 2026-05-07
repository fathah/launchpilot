import Foundation

nonisolated enum ArtifactRetention {
    /// Returns the build job ids that should be pruned for a given project.
    ///
    /// Jobs for the project are sorted by `startedAt` descending; everything
    /// beyond `keepLast` is returned for deletion. If the project has fewer
    /// jobs than the limit, returns empty.
    static func jobsToPrune(
        in jobs: [BuildJob],
        forProjectId projectId: UUID,
        keepLast: Int
    ) -> [BuildJob] {
        guard keepLast > 0 else { return [] }
        let projectJobs = jobs
            .filter { $0.projectId == projectId }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        guard projectJobs.count > keepLast else { return [] }
        return Array(projectJobs.dropFirst(keepLast))
    }

    /// Path to the persisted log file for a job.
    static func logURL(projectId: UUID, jobId: UUID) -> URL {
        AppConstants.logsDirectory
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
            .appendingPathComponent("\(jobId.uuidString).log")
    }
}
