import Foundation

protocol FrameworkAdapter: Sendable {
    var framework: Framework { get }
    var displayName: String { get }

    func detect(at path: URL) -> DetectionResult
    func validate(project: Project, config: ProjectConfig) -> [ValidationIssue]
}

extension FrameworkAdapter {
    func displayName(_: Void = ()) -> String { framework.displayName }
}

enum FrameworkDetector {
    static let adapters: [any FrameworkAdapter] = [
        FlutterAdapter(),
        ExpoAdapter(),
        ReactNativeAdapter(),
        NativeIOSAdapter(),
        NativeAndroidAdapter()
    ]

    static func detect(at path: URL) -> DetectionResult {
        let results = adapters.map { $0.detect(at: path) }
        return results.max(by: { $0.confidence < $1.confidence }) ?? .unknown
    }

    static func adapter(for framework: Framework) -> (any FrameworkAdapter)? {
        adapters.first(where: { $0.framework == framework })
    }
}

enum DetectionFS {
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func readText(_ url: URL, maxBytes: Int = 256_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    static func packageJSONContains(_ url: URL, key: String) -> Bool {
        let pkg = url.appendingPathComponent("package.json")
        guard exists(pkg), let text = readText(pkg) else { return false }
        return text.contains("\"\(key)\"")
    }
}
