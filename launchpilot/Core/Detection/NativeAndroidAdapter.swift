import Foundation

struct NativeAndroidAdapter: FrameworkAdapter {
    var framework: Framework { .nativeAndroid }
    var displayName: String { "Native Android" }

    func detect(at path: URL) -> DetectionResult {
        var evidence: [String] = []
        let candidates = [
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts"
        ]

        for name in candidates where DetectionFS.exists(path.appendingPathComponent(name)) {
            evidence.append(name)
        }

        guard !evidence.isEmpty else { return .unknown }

        if DetectionFS.exists(path.appendingPathComponent("pubspec.yaml")) ||
           DetectionFS.packageJSONContains(path, key: "react-native") {
            return DetectionResult(framework: .nativeAndroid, confidence: .low, evidence: evidence)
        }

        let hasSettings = evidence.contains(where: { $0.hasPrefix("settings.gradle") })
        let confidence: DetectionResult.Confidence = hasSettings ? .high : .medium
        return DetectionResult(framework: .nativeAndroid, confidence: confidence, evidence: evidence)
    }

    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let gradlew = project.url.appendingPathComponent("gradlew")
        if !DetectionFS.exists(gradlew) {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "gradlew not found",
                detail: "The Gradle wrapper is required to build the project."
            ))
        }
        return issues
    }
}
