import Foundation

enum BuildEngine {
    @MainActor
    static func start(
        project: Project,
        action: BuildAction,
        environment: String,
        config: ProjectConfig,
        credentials: [String: Credential] = [:],
        onComplete: @MainActor @escaping (BuildJob) -> Void
    ) throws -> BuildSession {
        let plan = try CommandPlanner.plan(action: action, project: project, config: config, credentials: credentials)
        let platform: Platform = (action == .buildIOSIPA) ? .iOS :
            (action == .buildAndroidAAB ? .android :
            (project.framework.supportsIOS ? .iOS : .android))

        let job = BuildJob(
            projectId: project.id,
            platform: platform,
            environment: environment,
            action: action
        )

        let session = BuildSession(
            job: job,
            project: project,
            stepLabels: plan.steps.map(\.label)
        )

        let logURL = AppConstants.logsDirectory
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent("\(job.id.uuidString).log")
        session.logFileURL = logURL

        Task.detached { [plan, session, project, logURL] in
            await runJob(session: session, plan: plan, project: project, logURL: logURL, onComplete: onComplete)
        }

        return session
    }

    @MainActor
    private static func setStatus(_ status: BuildStatus, on session: BuildSession) {
        session.status = status
    }

    private static func runJob(
        session: BuildSession,
        plan: PlannedBuild,
        project: Project,
        logURL: URL,
        onComplete: @MainActor @escaping (BuildJob) -> Void
    ) async {
        let writer = BuildLogWriter(url: logURL)
        do {
            try await writer.open()
        } catch {
            await MainActor.run {
                session.failureReason = "Could not open log file: \(error.localizedDescription)"
                session.status = .failed
                session.completedAt = Date()
            }
            return
        }

        await MainActor.run {
            session.startedAt = Date()
            session.status = .running
        }

        var failed = false
        var cancelled = false

        for (index, spec) in plan.steps.enumerated() {
            await MainActor.run {
                session.currentStepIndex = index
                session.stepStatuses[index] = .running
                session.append(LogLine(
                    stream: .stdout,
                    text: "▶ \(spec.label)",
                    timestamp: Date()
                ))
            }
            await writer.writeHeader(
                commandLabel: spec.label,
                executable: spec.executable,
                arguments: spec.arguments,
                workingDirectory: spec.workingDirectory.path
            )

            let stream = ProcessRunner.run(spec, cancellation: session.cancellation)
            var stepFailed = false
            var stepCancelled = false

            for await event in stream {
                switch event {
                case .started(_, _, let commandLine):
                    await MainActor.run {
                        session.resolvedCommandLines.append(commandLine)
                    }
                case .log(let line):
                    await writer.write(line)
                    await MainActor.run {
                        session.append(line)
                    }
                case .exited(let code):
                    if code != 0 {
                        stepFailed = true
                        await MainActor.run {
                            session.failureReason = "Step \"\(spec.label)\" exited with code \(code)."
                        }
                    }
                    await writer.writeFooter(exitCode: code, cancelled: false)
                case .failed(let message):
                    stepFailed = true
                    await MainActor.run {
                        session.failureReason = message
                        session.append(LogLine(stream: .stderr, text: message, timestamp: Date()))
                    }
                    await writer.writeFailure(message)
                    await writer.writeFooter(exitCode: nil, cancelled: false)
                case .cancelled:
                    stepCancelled = true
                    await writer.writeFooter(exitCode: nil, cancelled: true)
                }
            }

            if stepCancelled {
                cancelled = true
                await MainActor.run { session.stepStatuses[index] = .cancelled }
                break
            }
            if stepFailed {
                failed = true
                await MainActor.run { session.stepStatuses[index] = .failed }
                break
            }
            await MainActor.run { session.stepStatuses[index] = .succeeded }
        }

        let foundArtifacts = scanArtifacts(plan: plan, project: project, jobId: session.job.id)

        for url in plan.cleanupPaths {
            try? FileManager.default.removeItem(at: url)
        }

        await MainActor.run {
            session.completedAt = Date()
            session.artifacts = foundArtifacts
            if cancelled {
                session.status = .cancelled
            } else if failed {
                session.status = .failed
            } else {
                session.status = .succeeded
            }
        }

        await writer.close()

        let snapshot = await session.snapshotJob()
        await MainActor.run {
            onComplete(snapshot)
        }
    }

    private static func scanArtifacts(plan: PlannedBuild, project: Project, jobId: UUID) -> [BuildArtifact] {
        var found: [BuildArtifact] = []
        for expected in plan.expectedArtifacts {
            let dir = project.url.appendingPathComponent(expected.relativePath)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            let suffix = artifactSuffix(for: expected.type)
            for entry in contents where entry.hasSuffix(suffix) {
                let path = dir.appendingPathComponent(entry).path
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
                var artifact = BuildArtifact(
                    name: entry,
                    type: expected.type,
                    platform: expected.platform,
                    path: path,
                    buildId: jobId
                )
                artifact.sizeBytes = size
                found.append(artifact)
            }
        }
        return found
    }

    private static func artifactSuffix(for type: BuildArtifact.ArtifactType) -> String {
        switch type {
        case .xcarchive: return ".xcarchive"
        case .ipa: return ".ipa"
        case .aab: return ".aab"
        case .apk: return ".apk"
        case .logs: return ".log"
        }
    }
}
