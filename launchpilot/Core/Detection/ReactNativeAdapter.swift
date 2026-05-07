import Foundation

struct ReactNativeAdapter: FrameworkAdapter {
    var framework: Framework { .reactNative }
    var displayName: String { "React Native" }

    func detect(at path: URL) -> DetectionResult {
        var evidence: [String] = []
        let hasRN = DetectionFS.packageJSONContains(path, key: "react-native")
        guard hasRN else { return .unknown }
        evidence.append("react-native in package.json")

        let hasIOS = DetectionFS.isDirectory(path.appendingPathComponent("ios"))
        let hasAndroid = DetectionFS.isDirectory(path.appendingPathComponent("android"))
        if hasIOS { evidence.append("ios/ directory") }
        if hasAndroid { evidence.append("android/ directory") }

        if DetectionFS.packageJSONContains(path, key: "expo") {
            return DetectionResult(framework: .reactNative, confidence: .low, evidence: evidence)
        }

        let confidence: DetectionResult.Confidence = (hasIOS && hasAndroid) ? .high : .medium
        return DetectionResult(framework: .reactNative, confidence: confidence, evidence: evidence)
    }

    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let podfile = project.url.appendingPathComponent("ios/Podfile")
        if config.apps.ios?.enabled == true && !DetectionFS.exists(podfile) {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "ios/Podfile not found",
                detail: "React Native iOS builds need CocoaPods.",
                fixHint: "Run `cd ios && pod install`."
            ))
        }
        return issues
    }
}
