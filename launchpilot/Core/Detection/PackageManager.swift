import Foundation

nonisolated enum PackageManager: String, Codable, CaseIterable, Sendable, Identifiable {
    case npm
    case yarn
    case pnpm
    case bun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .pnpm: return "pnpm"
        case .bun: return "Bun"
        }
    }

    var executable: String { rawValue }

    var installArguments: [String] { ["install"] }

    static func detect(at url: URL) -> PackageManager? {
        let fs = FileManager.default
        let candidates: [(String, PackageManager)] = [
            ("bun.lockb", .bun),
            ("bun.lock", .bun),
            ("pnpm-lock.yaml", .pnpm),
            ("yarn.lock", .yarn),
            ("package-lock.json", .npm)
        ]
        for (file, pm) in candidates where fs.fileExists(atPath: url.appendingPathComponent(file).path) {
            return pm
        }
        if let text = DetectionFS.readText(url.appendingPathComponent("package.json")),
           let manager = parsePackageManagerField(text) {
            return manager
        }
        return nil
    }

    private static func parsePackageManagerField(_ text: String) -> PackageManager? {
        let pattern = #""packageManager"\s*:\s*"([a-z]+)@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return PackageManager(rawValue: String(text[r]))
    }
}
