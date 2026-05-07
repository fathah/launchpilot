import Foundation

struct ExpoAdapter: FrameworkAdapter {
    var framework: Framework { .expo }
    var displayName: String { "Expo" }

    func detect(at path: URL) -> DetectionResult {
        var evidence: [String] = []
        let appJson = path.appendingPathComponent("app.json")
        let appConfigJS = path.appendingPathComponent("app.config.js")
        let appConfigTS = path.appendingPathComponent("app.config.ts")

        if DetectionFS.exists(appJson) { evidence.append("app.json") }
        if DetectionFS.exists(appConfigJS) { evidence.append("app.config.js") }
        if DetectionFS.exists(appConfigTS) { evidence.append("app.config.ts") }

        let hasExpoDep = DetectionFS.packageJSONContains(path, key: "expo")
        if hasExpoDep { evidence.append("expo in package.json") }

        guard hasExpoDep || evidence.contains(where: { $0.hasPrefix("app.") }) else {
            return .unknown
        }

        let confidence: DetectionResult.Confidence
        if hasExpoDep && evidence.count >= 2 {
            confidence = .high
        } else if hasExpoDep {
            confidence = .medium
        } else {
            confidence = .low
        }
        return DetectionResult(framework: .expo, confidence: confidence, evidence: evidence)
    }

    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let iosDir = project.url.appendingPathComponent("ios")
        let androidDir = project.url.appendingPathComponent("android")
        if !DetectionFS.isDirectory(iosDir) && !DetectionFS.isDirectory(androidDir) {
            issues.append(ValidationIssue(
                severity: .info,
                title: "Native folders not generated",
                detail: "Local native builds need ios/ and android/ folders.",
                fixHint: "Run `npx expo prebuild` from the project root."
            ))
        }
        return issues
    }
}
