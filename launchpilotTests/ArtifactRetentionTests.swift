import Testing
import Foundation
@testable import launchpilot

struct ArtifactRetentionTests {

    private func makeJob(
        projectId: UUID,
        startedAt: Date
    ) -> BuildJob {
        var job = BuildJob(
            projectId: projectId,
            platform: .iOS,
            environment: "production",
            action: .buildIOSIPA
        )
        job.startedAt = startedAt
        return job
    }

    @Test func dropsJobsBeyondLimit() {
        let projectId = UUID()
        let now = Date()
        let jobs = (0..<5).map { idx in
            makeJob(projectId: projectId, startedAt: now.addingTimeInterval(TimeInterval(-idx * 60)))
        }
        let dropped = ArtifactRetention.jobsToPrune(
            in: jobs,
            forProjectId: projectId,
            keepLast: 3
        )
        #expect(dropped.count == 2)
        // Oldest two are dropped.
        let droppedTimestamps = dropped.compactMap(\.startedAt).sorted()
        let expectedOldest = [
            now.addingTimeInterval(-240),
            now.addingTimeInterval(-180)
        ]
        #expect(droppedTimestamps == expectedOldest)
    }

    @Test func returnsEmptyWhenUnderLimit() {
        let projectId = UUID()
        let jobs = (0..<3).map { idx in
            makeJob(projectId: projectId, startedAt: Date().addingTimeInterval(TimeInterval(-idx)))
        }
        let dropped = ArtifactRetention.jobsToPrune(
            in: jobs,
            forProjectId: projectId,
            keepLast: 10
        )
        #expect(dropped.isEmpty)
    }

    @Test func ignoresOtherProjects() {
        let target = UUID()
        let other = UUID()
        let now = Date()
        var jobs: [BuildJob] = []
        for i in 0..<5 {
            jobs.append(makeJob(projectId: target, startedAt: now.addingTimeInterval(TimeInterval(-i * 60))))
        }
        for i in 0..<5 {
            jobs.append(makeJob(projectId: other, startedAt: now.addingTimeInterval(TimeInterval(-i * 60))))
        }
        let dropped = ArtifactRetention.jobsToPrune(
            in: jobs,
            forProjectId: target,
            keepLast: 2
        )
        #expect(dropped.count == 3)
        #expect(dropped.allSatisfy { $0.projectId == target })
    }

    @Test func handlesMissingStartedAt() {
        let projectId = UUID()
        let now = Date()
        var jobWithDate = makeJob(projectId: projectId, startedAt: now)
        var jobWithoutDate = BuildJob(
            projectId: projectId,
            platform: .iOS,
            environment: "production",
            action: .buildIOSIPA
        )
        // jobWithoutDate.startedAt remains nil
        _ = jobWithoutDate

        let jobs = [jobWithoutDate, jobWithDate]
        let dropped = ArtifactRetention.jobsToPrune(
            in: jobs,
            forProjectId: projectId,
            keepLast: 1
        )
        // The job with a real date is most recent; the nil-date one is dropped.
        #expect(dropped.count == 1)
        #expect(dropped.first?.id == jobWithoutDate.id)
        _ = jobWithDate
    }

    @Test func zeroLimitDropsNothing() {
        // Defensive: keepLast: 0 is invalid input; the helper returns empty rather
        // than wiping all history. AppState clamps to >= 1, so this only matters
        // if the helper is called directly.
        let projectId = UUID()
        let jobs = [makeJob(projectId: projectId, startedAt: Date())]
        let dropped = ArtifactRetention.jobsToPrune(
            in: jobs,
            forProjectId: projectId,
            keepLast: 0
        )
        #expect(dropped.isEmpty)
    }
}
