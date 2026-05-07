import Foundation

struct DetectedFlavors: Sendable, Equatable {
    var androidFlavors: [String] = []
    var iosSchemes: [String] = []

    var hasAnything: Bool {
        !androidFlavors.isEmpty || !iosSchemes.isEmpty
    }
}

enum FlavorDetector {
    static func detect(at projectURL: URL, framework: Framework) -> DetectedFlavors {
        var result = DetectedFlavors()

        if let androidDir = androidRoot(at: projectURL, framework: framework) {
            result.androidFlavors = parseAndroidFlavors(in: androidDir)
        }

        if let iosDir = iosRoot(at: projectURL, framework: framework) {
            result.iosSchemes = parseIOSSchemes(in: iosDir)
        }

        return result
    }

    private static func androidRoot(at url: URL, framework: Framework) -> URL? {
        switch framework {
        case .nativeAndroid:
            return url
        case .reactNative, .expo, .flutter:
            let dir = url.appendingPathComponent("android")
            return DetectionFS.isDirectory(dir) ? dir : nil
        case .nativeIOS, .unknown:
            return nil
        }
    }

    private static func iosRoot(at url: URL, framework: Framework) -> URL? {
        switch framework {
        case .nativeIOS:
            return url
        case .reactNative, .expo, .flutter:
            let dir = url.appendingPathComponent("ios")
            return DetectionFS.isDirectory(dir) ? dir : nil
        case .nativeAndroid, .unknown:
            return nil
        }
    }

    // MARK: - Android

    private static func parseAndroidFlavors(in androidDir: URL) -> [String] {
        let candidates = [
            androidDir.appendingPathComponent("app/build.gradle"),
            androidDir.appendingPathComponent("app/build.gradle.kts")
        ]
        for url in candidates where DetectionFS.exists(url) {
            if let text = DetectionFS.readText(url, maxBytes: 512_000) {
                let flavors = extractAndroidFlavors(from: text)
                if !flavors.isEmpty { return flavors }
            }
        }
        return []
    }

    /// Pulls flavor names out of `productFlavors { foo { ... } bar { ... } }`
    /// (Groovy DSL) and `productFlavors { create("foo") { ... } }` (Kotlin DSL).
    static func extractAndroidFlavors(from gradle: String) -> [String] {
        guard let block = sliceBlock(after: "productFlavors", in: gradle) else { return [] }

        var flavors: [String] = []
        let reserved: Set<String> = ["if", "else", "for", "while", "dimension"]

        if let groovy = try? NSRegularExpression(pattern: #"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\{"#) {
            let range = NSRange(block.startIndex..., in: block)
            groovy.enumerateMatches(in: block, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1,
                      let r = Range(m.range(at: 1), in: block) else { return }
                let name = String(block[r])
                if !reserved.contains(name), !flavors.contains(name) {
                    flavors.append(name)
                }
            }
        }

        if let kotlin = try? NSRegularExpression(pattern: #"create\s*\(\s*["']([\w]+)["']\s*\)"#) {
            let range = NSRange(block.startIndex..., in: block)
            kotlin.enumerateMatches(in: block, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1,
                      let r = Range(m.range(at: 1), in: block) else { return }
                let name = String(block[r])
                if !flavors.contains(name) { flavors.append(name) }
            }
        }

        return flavors
    }

    /// Returns the brace-balanced body that follows the given keyword.
    private static func sliceBlock(after keyword: String, in source: String) -> String? {
        guard let start = source.range(of: keyword) else { return nil }
        var idx = start.upperBound
        while idx < source.endIndex, source[idx] != "{" {
            idx = source.index(after: idx)
        }
        guard idx < source.endIndex, source[idx] == "{" else { return nil }
        let openBrace = idx
        idx = source.index(after: idx)
        var depth = 1
        while idx < source.endIndex {
            switch source[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let body = source[source.index(after: openBrace)..<idx]
                    return String(body)
                }
            default: break
            }
            idx = source.index(after: idx)
        }
        return nil
    }

    // MARK: - iOS

    private static func parseIOSSchemes(in iosDir: URL) -> [String] {
        var schemes: Set<String> = []
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: iosDir.path) else { return [] }
        for entry in entries where entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace") {
            let dir = iosDir
                .appendingPathComponent(entry)
                .appendingPathComponent("xcshareddata/xcschemes")
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasSuffix(".xcscheme") {
                schemes.insert((file as NSString).deletingPathExtension)
            }
        }
        let cleaned = schemes.filter { name in
            let lower = name.lowercased()
            return !lower.contains("test") && !lower.contains("extension")
        }
        let pool = cleaned.isEmpty ? schemes : cleaned
        return pool.sorted()
    }
}
