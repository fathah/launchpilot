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

        for (index, step) in plan.steps.enumerated() {
            await MainActor.run {
                session.currentStepIndex = index
                session.stepStatuses[index] = .running
                session.append(LogLine(
                    stream: .stdout,
                    text: "▶ \(step.label)",
                    timestamp: Date()
                ))
            }

            let outcome: BuildStepResult
            switch step {
            case .process(let spec):
                outcome = await runProcessStep(spec: spec, session: session, writer: writer)
            case .task(_, let run):
                outcome = await runTaskStep(label: step.label, run: run, session: session, writer: writer)
            }

            switch outcome {
            case .succeeded:
                await MainActor.run { session.stepStatuses[index] = .succeeded }
            case .failed(let message):
                failed = true
                await MainActor.run {
                    session.stepStatuses[index] = .failed
                    if session.failureReason == nil {
                        session.failureReason = message
                    }
                }
            case .cancelled:
                cancelled = true
                await MainActor.run { session.stepStatuses[index] = .cancelled }
            }

            if failed || cancelled { break }
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

    private static func runProcessStep(
        spec: ProcessSpec,
        session: BuildSession,
        writer: BuildLogWriter
    ) async -> BuildStepResult {
        await writer.writeHeader(
            commandLabel: spec.label,
            executable: spec.executable,
            arguments: spec.arguments,
            workingDirectory: spec.workingDirectory.path
        )

        var stepFailed = false
        var stepCancelled = false
        var failureMessage: String?

        let stream = ProcessRunner.run(spec, cancellation: session.cancellation)
        for await event in stream {
            switch event {
            case .started(_, _, let commandLine):
                await MainActor.run { session.resolvedCommandLines.append(commandLine) }
            case .log(let line):
                await writer.write(line)
                await MainActor.run { session.append(line) }
            case .exited(let code):
                if code != 0 {
                    stepFailed = true
                    failureMessage = "Step \"\(spec.label)\" exited with code \(code)."
                }
                await writer.writeFooter(exitCode: code, cancelled: false)
            case .failed(let message):
                stepFailed = true
                failureMessage = message
                let errorLine = LogLine(stream: .stderr, text: message, timestamp: Date())
                await MainActor.run { session.append(errorLine) }
                await writer.writeFailure(message)
                await writer.writeFooter(exitCode: nil, cancelled: false)
            case .cancelled:
                stepCancelled = true
                await writer.writeFooter(exitCode: nil, cancelled: true)
            }
        }

        if stepCancelled { return .cancelled }
        if stepFailed { return .failed(message: failureMessage ?? "process failed") }
        return .succeeded
    }

    private static func runTaskStep(
        label: String,
        run: @Sendable (BuildTaskContext) async -> BuildStepResult,
        session: BuildSession,
        writer: BuildLogWriter
    ) async -> BuildStepResult {
        await writer.writeHeader(
            commandLabel: label,
            executable: "<launchpilot-task>",
            arguments: [],
            workingDirectory: ""
        )

        let cancellation = session.cancellation
        let context = BuildTaskContext(
            log: { line in
                await writer.write(line)
                await MainActor.run { session.append(line) }
            },
            isCancelled: { await cancellation.wasCancelled }
        )

        let result = await run(context)
        switch result {
        case .succeeded:
            await writer.writeFooter(exitCode: 0, cancelled: false)
        case .failed(let message):
            await writer.writeFailure(message)
            await writer.writeFooter(exitCode: nil, cancelled: false)
        case .cancelled:
            await writer.writeFooter(exitCode: nil, cancelled: true)
        }
        return result
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
