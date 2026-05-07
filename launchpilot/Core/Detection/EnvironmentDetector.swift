import Foundation

enum EnvironmentDetector {
    struct DetectedEnvironment: Hashable, Sendable {
        let key: String
        let displayName: String
    }

    static func detect(at projectURL: URL, framework: Framework) -> [DetectedEnvironment] {
        var collected: [String] = []

        if framework.supportsAndroid {
            let androidRoot: URL = (framework == .nativeAndroid)
                ? projectURL
                : projectURL.appendingPathComponent("android")
            collected.append(contentsOf: androidProductFlavors(at: androidRoot))
        }

        if framework.supportsIOS {
            let iosRoot: URL = (framework == .nativeIOS)
                ? projectURL
                : projectURL.appendingPathComponent("ios")
            collected.append(contentsOf: iosSchemeNames(at: iosRoot))
        }

        return canonicalize(collected)
    }

    // MARK: - Android

    private static func androidProductFlavors(at dir: URL) -> [String] {
        let candidates = [
            dir.appendingPathComponent("app/build.gradle"),
            dir.appendingPathComponent("app/build.gradle.kts"),
            dir.appendingPathComponent("build.gradle"),
            dir.appendingPathComponent("build.gradle.kts")
        ]
        for url in candidates where DetectionFS.exists(url) {
            if let text = DetectionFS.readText(url, maxBytes: 512_000) {
                let names = parseProductFlavors(text)
                if !names.isEmpty { return names }
            }
        }
        return []
    }

    static func parseProductFlavors(_ text: String) -> [String] {
        guard let blockRange = findBlock(in: text, header: "productFlavors") else { return [] }
        let block = String(text[blockRange])

        // Kotlin DSL: create("name") { ... }
        var names = matches(in: block, pattern: #"create\s*\(\s*["']([A-Za-z][\w]*)["']"#)
        if !names.isEmpty { return names }

        // Groovy DSL: top-level identifiers followed by `{`
        names = topLevelIdentifiers(in: block)
        return names
    }

    private static func findBlock(in text: String, header: String) -> Range<String.Index>? {
        guard let headerRange = text.range(of: #"\b\#(header)\s*\{"#, options: .regularExpression) else { return nil }
        var depth = 0
        var idx = headerRange.upperBound
        // headerRange ends just after the opening `{`
        depth = 1
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return headerRange.upperBound..<idx
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func topLevelIdentifiers(in block: String) -> [String] {
        var depth = 0
        var current = ""
        var collected: [String] = []
        var idx = block.startIndex
        while idx < block.endIndex {
            let ch = block[idx]
            if ch == "{" {
                if depth == 0 {
                    let trimmed = current
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .newlines).last ?? ""
                    let token = trimmed.trimmingCharacters(in: .whitespaces)
                    if isIdentifier(token) {
                        collected.append(token)
                    }
                }
                depth += 1
                current = ""
            } else if ch == "}" {
                depth = max(0, depth - 1)
                current = ""
            } else if depth == 0 {
                current.append(ch)
            }
            idx = block.index(after: idx)
        }
        return collected
    }

    private static func isIdentifier(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - iOS

    private static func iosSchemeNames(at iosDir: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: iosDir.path) else { return [] }
        var roots: [URL] = []
        for name in entries where name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
            roots.append(iosDir.appendingPathComponent(name))
        }
        var schemes: [String] = []
        for root in roots {
            schemes.append(contentsOf: schemesIn(container: root))
        }
        return stripCommonAppPrefix(schemes)
    }

    /// Strip a shared app-name prefix (e.g. "MyAppDev", "MyAppStaging" → "Dev", "Staging").
    /// Only strips if at least two schemes share a non-trivial prefix that ends at a
    /// case boundary, leaving a recognizable env token behind.
    static func stripCommonAppPrefix(_ schemes: [String]) -> [String] {
        guard schemes.count >= 2 else { return schemes }
        let prefix = longestCommonPrefix(schemes)
        guard prefix.count >= 3 else { return schemes }
        // Only strip up to the last lowercase→uppercase boundary so we don't
        // chop into the env name itself.
        let cutoff = caseBoundaryEnd(prefix) ?? prefix.endIndex
        let strip = String(prefix[..<cutoff])
        guard strip.count >= 3 else { return schemes }
        return schemes.map { name in
            if name.hasPrefix(strip), name.count > strip.count {
                return String(name.dropFirst(strip.count))
            }
            return name
        }
    }

    private static func longestCommonPrefix(_ values: [String]) -> String {
        guard let first = values.first else { return "" }
        var prefix = first
        for s in values.dropFirst() {
            while !s.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }

    /// Returns the index just after the last lowercase letter that is followed
    /// by an uppercase letter — i.e. a camelCase word boundary.
    private static func caseBoundaryEnd(_ s: String) -> String.Index? {
        var last: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(after: i)
            if next < s.endIndex,
               s[i].isLowercase,
               s[next].isUppercase {
                last = next
            }
            i = next
        }
        return last
    }

    private static func schemesIn(container: URL) -> [String] {
        let dir = container.appendingPathComponent("xcshareddata/xcschemes")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return entries
            .filter { $0.hasSuffix(".xcscheme") }
            .map { String($0.dropLast(".xcscheme".count)) }
            .filter { !$0.lowercased().hasPrefix("pods") }
    }

    // MARK: - Canonicalization

    private static let aliasMap: [String: String] = [
        "development": "dev",
        "develop": "dev",
        "qa": "staging",
        "stage": "staging",
        "uat": "staging",
        "preprod": "staging",
        "preproduction": "staging",
        "prod": "production",
        "release": "production",
        "live": "production"
    ]

    private static let blocklist: Set<String> = [
        "debug", "release", "main", "default", "runner", "app", "test", "tests"
    ]

    private static func canonicalize(_ raw: [String]) -> [DetectedEnvironment] {
        var seen: Set<String> = []
        var ordered: [DetectedEnvironment] = []
        for value in raw {
            guard let key = canonicalKey(for: value) else { continue }
            if seen.insert(key).inserted {
                ordered.append(DetectedEnvironment(key: key, displayName: displayName(for: key)))
            }
        }
        return ordered
    }

    private static func canonicalKey(for raw: String) -> String? {
        var s = raw.lowercased()
        // Strip common config prefixes/suffixes used in iOS schemes / configs.
        let stripPrefixes = ["debug-", "debug.", "debug_", "release-", "release.", "release_"]
        for p in stripPrefixes where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        let stripSuffixes = ["-debug", ".debug", "_debug", "-release", ".release", "_release"]
        for sfx in stripSuffixes where s.hasSuffix(sfx) { s = String(s.dropLast(sfx.count)) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-._ "))
        if s.isEmpty { return nil }
        if let alias = aliasMap[s] { s = alias }
        if blocklist.contains(s) { return nil }
        guard !s.isEmpty else { return nil }
        return s
    }

    private static func displayName(for key: String) -> String {
        guard let first = key.first else { return key }
        return first.uppercased() + key.dropFirst()
    }

    // MARK: - Regex helper

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return }
            out.append(String(text[r]))
        }
        return out
    }
}
