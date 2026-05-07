import Foundation

enum BundleIDDetector {
    static func detect(at projectURL: URL, framework: Framework) -> (iosBundleId: String?, androidPackage: String?) {
        switch framework {
        case .flutter:
            return (iosBundleIdFromXcodeProject(at: projectURL.appendingPathComponent("ios/Runner.xcodeproj")),
                    androidPackageFromGradle(at: projectURL.appendingPathComponent("android")))
        case .reactNative:
            return (iosBundleIdFromIOSDir(projectURL.appendingPathComponent("ios")),
                    androidPackageFromGradle(at: projectURL.appendingPathComponent("android")))
        case .expo:
            let prebuilt = (
                iosBundleIdFromIOSDir(projectURL.appendingPathComponent("ios")),
                androidPackageFromGradle(at: projectURL.appendingPathComponent("android"))
            )
            if prebuilt.0 != nil || prebuilt.1 != nil { return prebuilt }
            return expoAppConfig(at: projectURL)
        case .nativeIOS:
            return (iosBundleIdFromIOSDir(projectURL), nil)
        case .nativeAndroid:
            return (nil, androidPackageFromGradle(at: projectURL))
        case .unknown:
            return (nil, nil)
        }
    }

    // MARK: - iOS

    private static func iosBundleIdFromIOSDir(_ dir: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }
        if let first = projects.first {
            return iosBundleIdFromXcodeProject(at: dir.appendingPathComponent(first))
        }
        if let workspace = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return iosBundleIdFromWorkspace(dir.appendingPathComponent(workspace))
        }
        return nil
    }

    private static func iosBundleIdFromWorkspace(_ url: URL) -> String? {
        let dataFile = url.appendingPathComponent("contents.xcworkspacedata")
        guard let xml = DetectionFS.readText(dataFile) else { return nil }
        let pattern = #"location\s*=\s*"[^"]*?([\w.-]+\.xcodeproj)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        let projectName = String(xml[range])
        let parent = url.deletingLastPathComponent()
        return iosBundleIdFromXcodeProject(at: parent.appendingPathComponent(projectName))
    }

    static func iosBundleIdFromXcodeProject(at projectURL: URL) -> String? {
        let pbx = projectURL.appendingPathComponent("project.pbxproj")
        guard let text = DetectionFS.readText(pbx, maxBytes: 2_000_000) else { return nil }
        let pattern = #"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\n]+)"?\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        var hits: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return }
            let value = String(text[r]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !value.contains("$(") else { return }
            hits.append(value)
        }

        // Prefer the most common, excluding test bundles when alternatives exist.
        let nonTest = hits.filter { !$0.lowercased().contains("test") }
        let pool = nonTest.isEmpty ? hits : nonTest
        guard !pool.isEmpty else { return nil }
        let counts = Dictionary(grouping: pool, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Android

    private static func androidPackageFromGradle(at dir: URL) -> String? {
        let candidates = [
            dir.appendingPathComponent("app/build.gradle"),
            dir.appendingPathComponent("app/build.gradle.kts"),
            dir.appendingPathComponent("build.gradle"),
            dir.appendingPathComponent("build.gradle.kts")
        ]
        for url in candidates where DetectionFS.exists(url) {
            if let pkg = parseGradlePackage(at: url) { return pkg }
        }
        return nil
    }

    private static func parseGradlePackage(at url: URL) -> String? {
        guard let text = DetectionFS.readText(url) else { return nil }
        let patterns = [
            #"applicationId\s+["']([\w.]+)["']"#,
            #"applicationId\s*=\s*["']([\w.]+)["']"#,
            #"namespace\s+["']([\w.]+)["']"#,
            #"namespace\s*=\s*["']([\w.]+)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: text) {
                return String(text[r])
            }
        }
        return nil
    }

    // MARK: - Expo

    private static func expoAppConfig(at projectURL: URL) -> (String?, String?) {
        if let json = readAppJSON(at: projectURL.appendingPathComponent("app.json")) {
            return json
        }
        for name in ["app.config.js", "app.config.ts"] {
            let url = projectURL.appendingPathComponent(name)
            guard DetectionFS.exists(url), let text = DetectionFS.readText(url) else { continue }
            let ios = firstMatch(in: text, pattern: #"bundleIdentifier\s*:\s*["']([\w.\-]+)["']"#)
            let android = firstMatch(in: text, pattern: #"\bpackage\s*:\s*["']([\w.\-]+)["']"#)
            if ios != nil || android != nil { return (ios, android) }
        }
        return (nil, nil)
    }

    private static func readAppJSON(at url: URL) -> (String?, String?)? {
        guard DetectionFS.exists(url),
              let data = try? Data(contentsOf: url),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let root = (any["expo"] as? [String: Any]) ?? any
        let ios = (root["ios"] as? [String: Any])?["bundleIdentifier"] as? String
        let android = (root["android"] as? [String: Any])?["package"] as? String
        return (ios, android)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
