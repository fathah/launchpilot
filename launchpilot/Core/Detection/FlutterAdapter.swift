import Foundation

struct FlutterAdapter: FrameworkAdapter {
    var framework: Framework { .flutter }
    var displayName: String { "Flutter" }

    func detect(at path: URL) -> DetectionResult {
        var evidence: [String] = []
        let pubspec = path.appendingPathComponent("pubspec.yaml")
        guard DetectionFS.exists(pubspec) else { return .unknown }
        evidence.append("pubspec.yaml")

        if let text = DetectionFS.readText(pubspec), text.contains("flutter:") {
            evidence.append("flutter section in pubspec.yaml")
        }

        if DetectionFS.isDirectory(path.appendingPathComponent("ios")) {
            evidence.append("ios/ directory")
        }
        if DetectionFS.isDirectory(path.appendingPathComponent("android")) {
            evidence.append("android/ directory")
        }

        let confidence: DetectionResult.Confidence = evidence.count >= 3 ? .high : .medium
        return DetectionResult(framework: .flutter, confidence: confidence, evidence: evidence)
    }

    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if config.apps.ios?.enabled == true && config.apps.ios?.bundleId?.isEmpty != false {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "iOS bundle ID is missing",
                detail: "Set ios.bundle_id in launchpilot.yaml before archiving."
            ))
        }
        if config.apps.android?.enabled == true && config.apps.android?.packageName?.isEmpty != false {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "Android package name is missing",
                detail: "Set android.package_name in launchpilot.yaml before building."
            ))
        }
        return issues
    }
}
