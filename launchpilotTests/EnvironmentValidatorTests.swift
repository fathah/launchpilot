import Testing
import Foundation
@testable import launchpilot

struct EnvironmentValidatorTests {

    private func ids(_ checks: [EnvironmentCheck]) -> Set<String> {
        Set(checks.map(\.id))
    }

    @Test func flutterIncludesXcodeJavaCocoaPodsAndroidSDKAndFlutter() async {
        let checks = await EnvironmentValidator.checks(framework: .flutter, packageManager: nil)
        let ids = ids(checks)
        #expect(ids.contains("xcodebuild"))
        #expect(ids.contains("cocoapods"))
        #expect(ids.contains("java"))
        #expect(ids.contains("android_sdk"))
        #expect(ids.contains("flutter"))
        #expect(ids.contains("git"))
    }

    @Test func nativeIOSDoesNotIncludeAndroidTooling() async {
        let checks = await EnvironmentValidator.checks(framework: .nativeIOS, packageManager: nil)
        let ids = ids(checks)
        #expect(ids.contains("xcodebuild"))
        #expect(ids.contains("git"))
        #expect(!ids.contains("java"))
        #expect(!ids.contains("android_sdk"))
        #expect(!ids.contains("adb"))
        #expect(!ids.contains("flutter"))
        #expect(!ids.contains("cocoapods"))
        #expect(!ids.contains("node"))
    }

    @Test func nativeAndroidIncludesGradleAndAndroidSDK() async {
        let checks = await EnvironmentValidator.checks(framework: .nativeAndroid, packageManager: nil)
        let ids = ids(checks)
        #expect(ids.contains("java"))
        #expect(ids.contains("android_sdk"))
        #expect(ids.contains("adb"))
        #expect(ids.contains("gradle"))
        #expect(!ids.contains("xcodebuild"))
        #expect(!ids.contains("cocoapods"))
    }

    @Test func reactNativeIncludesPackageManager() async {
        let checks = await EnvironmentValidator.checks(framework: .reactNative, packageManager: .pnpm)
        let ids = ids(checks)
        #expect(ids.contains("xcodebuild"))
        #expect(ids.contains("cocoapods"))
        #expect(ids.contains("node"))
        #expect(ids.contains("pnpm"))
        #expect(ids.contains("java"))
        #expect(ids.contains("android_sdk"))
    }

    @Test func reactNativeWithoutPackageManagerSkipsPM() async {
        let checks = await EnvironmentValidator.checks(framework: .reactNative, packageManager: nil)
        let ids = ids(checks)
        #expect(ids.contains("node"))
        // No PM check when nil — neither npm/yarn/pnpm/bun ids should appear
        #expect(!ids.contains("npm"))
        #expect(!ids.contains("yarn"))
        #expect(!ids.contains("pnpm"))
        #expect(!ids.contains("bun"))
    }

    @Test func unknownFrameworkOnlyChecksGit() async {
        let checks = await EnvironmentValidator.checks(framework: .unknown, packageManager: nil)
        let ids = ids(checks)
        #expect(ids == ["git"])
    }

    @Test func resultsAreStablyOrdered() async {
        let a = await EnvironmentValidator.checks(framework: .flutter, packageManager: nil)
        let b = await EnvironmentValidator.checks(framework: .flutter, packageManager: nil)
        #expect(a.map(\.id) == b.map(\.id))
    }

    @Test func gitHasResolvedVersionOnDevMac() async {
        // /usr/bin/git ships with macOS Command Line Tools — running these tests
        // implies CLT is installed, so this should always succeed in this repo.
        let checks = await EnvironmentValidator.checks(framework: .unknown, packageManager: nil)
        guard let git = checks.first(where: { $0.id == "git" }) else {
            Issue.record("expected git check")
            return
        }
        if case .ok(let version) = git.status {
            #expect(version?.contains("git") == true)
        } else {
            Issue.record("git check did not resolve to .ok: \(git.status)")
        }
    }
}
