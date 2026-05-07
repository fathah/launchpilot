import Foundation

struct NativeIOSAdapter: FrameworkAdapter {
    var framework: Framework { .nativeIOS }
    var displayName: String { "Native iOS" }

    func detect(at path: URL) -> DetectionResult {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path.path) else {
            return .unknown
        }

        var evidence: [String] = []
        let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }
        evidence.append(contentsOf: workspaces)
        evidence.append(contentsOf: projects)

        guard !workspaces.isEmpty || !projects.isEmpty else { return .unknown }

        if DetectionFS.exists(path.appendingPathComponent("pubspec.yaml")) ||
           DetectionFS.packageJSONContains(path, key: "react-native") {
            return DetectionResult(framework: .nativeIOS, confidence: .low, evidence: evidence)
        }

        let confidence: DetectionResult.Confidence = !workspaces.isEmpty ? .high : .medium
        return DetectionResult(framework: .nativeIOS, confidence: confidence, evidence: evidence)
    }

    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if config.apps.ios?.scheme?.isEmpty != false {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "iOS scheme not selected",
                detail: "Pick a scheme in launchpilot.yaml under apps.ios.scheme."
            ))
        }
        return issues
    }
}
