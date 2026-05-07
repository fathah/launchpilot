import Foundation

/// Pre-flight checks for the local toolchain. Runs once per project on demand
/// (background Task) — results are cached in `AppState.environmentChecks`.
nonisolated enum EnvironmentValidator {

    static func checks(
        framework: Framework,
        packageManager: PackageManager?
    ) async -> [EnvironmentCheck] {
        let env = await EnvironmentResolver.shared.environment(merging: nil)
        let specs = toolSpecs(for: framework, packageManager: packageManager)

        let pairs = await withTaskGroup(of: (Int, EnvironmentCheck).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask { (index, await runCheck(spec, env: env)) }
            }
            var collected: [(Int, EnvironmentCheck)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted(by: { $0.0 < $1.0 })
        }
        return pairs.map(\.1)
    }

    // MARK: - Tool selection

    private enum ToolSpec {
        case git
        case xcodebuild
        case cocoapods
        case java
        case androidSDK
        case adb
        case gradle
        case flutter
        case node
        case packageManager(PackageManager)
    }

    private static func toolSpecs(
        for framework: Framework,
        packageManager: PackageManager?
    ) -> [ToolSpec] {
        var specs: [ToolSpec] = [.git]

        if framework.supportsIOS {
            specs.append(.xcodebuild)
            if framework == .reactNative || framework == .expo || framework == .flutter {
                specs.append(.cocoapods)
            }
        }
        if framework.supportsAndroid {
            specs.append(.java)
            specs.append(.androidSDK)
            specs.append(.adb)
            if framework == .nativeAndroid {
                specs.append(.gradle)
            }
        }
        switch framework {
        case .flutter:
            specs.append(.flutter)
        case .expo, .reactNative:
            specs.append(.node)
            if let pm = packageManager {
                specs.append(.packageManager(pm))
            }
        default: break
        }
        return specs
    }

    // MARK: - Running checks

    private static func runCheck(_ spec: ToolSpec, env: [String: String]) async -> EnvironmentCheck {
        switch spec {
        case .git:
            return await toolCheck(
                id: "git",
                name: "git",
                detail: "Source control",
                severity: .recommended,
                executable: "git",
                versionArgs: ["--version"],
                installHint: "Install Xcode Command Line Tools: `xcode-select --install`",
                env: env
            )

        case .xcodebuild:
            return await toolCheck(
                id: "xcodebuild",
                name: "Xcode (xcodebuild)",
                detail: "Required for iOS archive + export",
                severity: .required,
                executable: "xcodebuild",
                versionArgs: ["-version"],
                installHint: "Install Xcode from the App Store, then run `sudo xcode-select -s /Applications/Xcode.app`",
                env: env
            )

        case .cocoapods:
            return await toolCheck(
                id: "cocoapods",
                name: "CocoaPods",
                detail: "Manages iOS native dependencies",
                severity: .required,
                executable: "pod",
                versionArgs: ["--version"],
                installHint: "Install: `sudo gem install cocoapods` or `brew install cocoapods`",
                env: env
            )

        case .java:
            return await toolCheck(
                id: "java",
                name: "Java",
                detail: "Required by Gradle",
                severity: .required,
                executable: "java",
                versionArgs: ["-version"],
                versionFromStderr: true,
                installHint: "Install JDK 17 (Temurin): `brew install --cask temurin@17`",
                env: env
            )

        case .androidSDK:
            return checkAndroidSDK(env: env)

        case .adb:
            return await toolCheck(
                id: "adb",
                name: "adb",
                detail: "Android Debug Bridge",
                severity: .recommended,
                executable: "adb",
                versionArgs: ["--version"],
                installHint: "Install Android SDK Platform Tools: `brew install --cask android-platform-tools`",
                env: env
            )

        case .gradle:
            return await toolCheck(
                id: "gradle",
                name: "gradle",
                detail: "Build tool — your project's `gradlew` is preferred when present",
                severity: .optional,
                executable: "gradle",
                versionArgs: ["--version"],
                installHint: "Most projects use the Gradle wrapper (`./gradlew`); a system gradle is optional.",
                env: env
            )

        case .flutter:
            return await toolCheck(
                id: "flutter",
                name: "Flutter",
                detail: "Flutter SDK on PATH",
                severity: .required,
                executable: "flutter",
                versionArgs: ["--version"],
                installHint: "Install Flutter and add `flutter/bin` to your `~/.zshrc` PATH.",
                env: env
            )

        case .node:
            return await toolCheck(
                id: "node",
                name: "Node.js",
                detail: "Required by RN / Expo",
                severity: .required,
                executable: "node",
                versionArgs: ["--version"],
                installHint: "Install Node 20+: `brew install node` (or use nvm/fnm)",
                env: env
            )

        case .packageManager(let pm):
            return await toolCheck(
                id: pm.executable,
                name: pm.displayName,
                detail: "Package manager for this project",
                severity: .required,
                executable: pm.executable,
                versionArgs: ["--version"],
                installHint: installHint(for: pm),
                env: env
            )
        }
    }

    private static func installHint(for pm: PackageManager) -> String {
        switch pm {
        case .npm: return "npm ships with Node.js."
        case .yarn: return "Install: `npm install -g yarn` or `corepack enable`"
        case .pnpm: return "Install: `npm install -g pnpm` or `corepack enable`"
        case .bun: return "Install: `brew install bun` or `curl -fsSL https://bun.sh/install | bash`"
        }
    }

    // MARK: - Check primitives

    private static func toolCheck(
        id: String,
        name: String,
        detail: String?,
        severity: EnvironmentCheck.Severity,
        executable: String,
        versionArgs: [String],
        versionFromStderr: Bool = false,
        installHint: String?,
        env: [String: String]
    ) async -> EnvironmentCheck {
        guard let resolvedPath = resolveExecutable(executable, env: env) else {
            return EnvironmentCheck(
                id: id,
                displayName: name,
                detail: detail,
                severity: severity,
                status: .missing,
                installHint: installHint
            )
        }

        let result = await runProcess(
            executable: resolvedPath,
            args: versionArgs,
            env: env,
            captureStderr: versionFromStderr
        )
        if result.exitCode == 0, let version = firstNonEmptyLine(result.output) {
            return EnvironmentCheck(
                id: id,
                displayName: name,
                detail: detail,
                severity: severity,
                status: .ok(version: version),
                installHint: nil
            )
        }
        if result.exitCode == 0 {
            return EnvironmentCheck(
                id: id,
                displayName: name,
                detail: detail,
                severity: severity,
                status: .ok(version: nil),
                installHint: nil
            )
        }
        return EnvironmentCheck(
            id: id,
            displayName: name,
            detail: detail,
            severity: severity,
            status: .error("`\(executable) \(versionArgs.joined(separator: " "))` exited with \(result.exitCode)"),
            installHint: installHint
        )
    }

    private static func checkAndroidSDK(env: [String: String]) -> EnvironmentCheck {
        let candidates = [
            env["ANDROID_HOME"],
            env["ANDROID_SDK_ROOT"],
            "\(env["HOME"] ?? NSHomeDirectory())/Library/Android/sdk"
        ].compactMap { $0 }.filter { !$0.isEmpty }

        let baseInfo = "Looked for ANDROID_HOME / ANDROID_SDK_ROOT and ~/Library/Android/sdk."
        let installHint = "Install Android Studio, then export `ANDROID_HOME=$HOME/Library/Android/sdk` in `~/.zprofile`."

        for path in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return EnvironmentCheck(
                    id: "android_sdk",
                    displayName: "Android SDK",
                    detail: path,
                    severity: .required,
                    status: .ok(version: nil),
                    installHint: nil
                )
            }
        }

        return EnvironmentCheck(
            id: "android_sdk",
            displayName: "Android SDK",
            detail: baseInfo,
            severity: .required,
            status: .missing,
            installHint: installHint
        )
    }

    // MARK: - Subprocess helpers

    private struct ToolResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    private static func runProcess(
        executable: String,
        args: [String],
        env: [String: String],
        captureStderr: Bool
    ) async -> ToolResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ToolResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                if captureStderr {
                    process.standardError = pipe
                } else {
                    process.standardError = Pipe()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ToolResult(exitCode: -1, output: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ToolResult(
                    exitCode: process.terminationStatus,
                    output: output
                ))
            }
        }
    }

    private static func resolveExecutable(_ name: String, env: [String: String]) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func firstNonEmptyLine(_ s: String) -> String? {
        for raw in s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
