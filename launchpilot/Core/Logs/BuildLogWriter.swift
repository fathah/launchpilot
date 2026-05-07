import Foundation

actor BuildLogWriter {
    private let url: URL
    private var handle: FileHandle?

    init(url: URL) {
        self.url = url
    }

    var fileURL: URL { url }

    func open() throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
    }

    func writeHeader(commandLabel: String, executable: String, arguments: [String], workingDirectory: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []
        lines.append("# launchpilot build log")
        lines.append("# label: \(commandLabel)")
        lines.append("# executable: \(executable)")
        lines.append("# arguments: \(arguments.joined(separator: " "))")
        lines.append("# cwd: \(workingDirectory)")
        lines.append("# started: \(timestamp)")
        lines.append("")
        write(lines.joined(separator: "\n") + "\n")
    }

    func write(_ line: LogLine) {
        let prefix = line.stream == .stderr ? "[stderr] " : ""
        write(prefix + line.text + "\n")
    }

    func writeFooter(exitCode: Int32?, cancelled: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let summary: String
        if cancelled {
            summary = "# cancelled at \(timestamp)"
        } else if let code = exitCode {
            summary = "# exited \(code) at \(timestamp)"
        } else {
            summary = "# finished at \(timestamp)"
        }
        write("\n" + summary + "\n")
    }

    private func write(_ text: String) {
        guard let handle, let data = text.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }
}
