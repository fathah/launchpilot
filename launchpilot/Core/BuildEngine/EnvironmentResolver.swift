import Foundation

actor EnvironmentResolver {
    static let shared = EnvironmentResolver()

    private var cached: [String: String]?

    func environment(merging extras: [String: String]?) async -> [String: String] {
        var env = await loginShellEnvironment()
        if let extras {
            for (key, value) in extras {
                env[key] = value
            }
        }
        return env
    }

    func refresh() async {
        cached = nil
        _ = await loginShellEnvironment()
    }

    private func loginShellEnvironment() async -> [String: String] {
        if let cached { return cached }
        let env = await Self.captureLoginShellEnvironment()
        cached = env
        return env
    }

    private static func captureLoginShellEnvironment() async -> [String: String] {
        var fallback = ProcessInfo.processInfo.environment
        fallback["PATH"] = fallback["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -i sources .zshrc / .bashrc where most users put SDK PATH exports
        // (Flutter, Android SDK, nvm, etc.). -l also runs login files.
        process.arguments = ["-ilc", "/usr/bin/env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return fallback
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return fallback }

        var env = fallback
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq])
            let value = String(line[line.index(after: eq)...])
            env[key] = value
        }
        return env
    }
}
