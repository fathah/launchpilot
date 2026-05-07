import Foundation

struct Diagnosis: Equatable, Sendable {
    let title: String
    let explanation: String
    let suggestion: String
}

enum ErrorDiagnoser {
    static func diagnose(failureReason: String?, logText: String) -> Diagnosis? {
        let haystack = (failureReason ?? "") + "\n" + logText
        for rule in rules {
            if rule.matches(haystack) {
                return rule.diagnosis
            }
        }
        return nil
    }

    static func diagnose(failureReason: String?, lines: [LogLine]) -> Diagnosis? {
        let text = lines.map(\.text).joined(separator: "\n")
        return diagnose(failureReason: failureReason, logText: text)
    }

    private struct Rule {
        let patterns: [String]
        let diagnosis: Diagnosis

        func matches(_ text: String) -> Bool {
            patterns.contains { text.range(of: $0, options: .caseInsensitive) != nil }
        }
    }

    private static let rules: [Rule] = [
        Rule(
            patterns: [
                "Could not find 'flutter' on PATH",
                "Could not find 'xcodebuild' on PATH",
                "Could not find 'gradle' on PATH",
                "Could not find 'pod' on PATH",
                "Could not find 'node' on PATH",
                "Could not find 'npx' on PATH",
                "Could not find 'java' on PATH",
                "Could not find 'adb' on PATH"
            ],
            diagnosis: Diagnosis(
                title: "Required tool isn't on launchpilot's PATH",
                explanation: "launchpilot launches builds with the PATH it captures from your login shell. The tool you need isn't in that PATH — usually because your SDK export lives in a file that wasn't sourced (for example `~/.zshrc` only runs for interactive shells).",
                suggestion: "Move the SDK export into `~/.zprofile` (or symlink the binary into `/usr/local/bin`), then quit and relaunch launchpilot so it re-reads the environment."
            )
        ),
        Rule(
            patterns: [
                "Provisioning profile doesn't support the Push Notifications capability",
                "Provisioning profile doesn't include the aps-environment entitlement"
            ],
            diagnosis: Diagnosis(
                title: "Provisioning profile is missing Push Notifications",
                explanation: "Your app declares the Push Notifications entitlement, but the provisioning profile Xcode picked doesn't include `aps-environment`.",
                suggestion: "In Apple Developer, enable Push Notifications for this App ID, regenerate the provisioning profile, and re-download it (or let Xcode manage signing automatically)."
            )
        ),
        Rule(
            patterns: [
                "No profiles for '.*' were found",
                "No signing certificate \"iOS Distribution\" found"
            ],
            diagnosis: Diagnosis(
                title: "No matching iOS signing assets",
                explanation: "Xcode could not find a provisioning profile or distribution certificate for this bundle ID + team combination.",
                suggestion: "Open the project in Xcode, sign in to your Apple ID under Settings → Accounts, and make sure Automatic Signing is on for the selected team. Then retry the build."
            )
        ),
        Rule(
            patterns: [
                "Code signing is required for product type",
                "requires a development team"
            ],
            diagnosis: Diagnosis(
                title: "Code signing is not configured",
                explanation: "The Xcode target needs a development team, but none is selected for the Release configuration.",
                suggestion: "Set a team under Signing & Capabilities for the target, or add `team_id` under `apps.ios` in `launchpilot.yaml`."
            )
        ),
        Rule(
            patterns: [
                "Keystore was tampered with, or password was incorrect",
                "Failed to read key .* from store"
            ],
            diagnosis: Diagnosis(
                title: "Android keystore credentials are wrong",
                explanation: "Gradle could open the keystore file but the password, alias, or key password doesn't match.",
                suggestion: "Update the stored keystore credentials in launchpilot Credentials, or re-check `signingConfigs.release` in `app/build.gradle`."
            )
        ),
        Rule(
            patterns: [
                "SDK location not found",
                "ANDROID_HOME is not set",
                "ANDROID_SDK_ROOT is not set"
            ],
            diagnosis: Diagnosis(
                title: "Android SDK location is missing",
                explanation: "Gradle can't find the Android SDK. It looks for `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `local.properties` with `sdk.dir`.",
                suggestion: "Add a `local.properties` file at the Android project root with `sdk.dir=/Users/<you>/Library/Android/sdk`, or export `ANDROID_HOME` in `~/.zprofile`."
            )
        ),
        Rule(
            patterns: [
                "CocoaPods could not find compatible versions",
                "Unable to find a specification",
                "pod install: command not found"
            ],
            diagnosis: Diagnosis(
                title: "CocoaPods problem",
                explanation: "CocoaPods either isn't installed, or your Podfile resolves to a version that no longer exists in the spec repo.",
                suggestion: "Run `sudo gem install cocoapods` if missing, then `pod repo update` and `pod install` from the `ios/` directory."
            )
        ),
        Rule(
            patterns: [
                "Flutter SDK at .* is not valid",
                "Unable to find git in your PATH"
            ],
            diagnosis: Diagnosis(
                title: "Flutter SDK can't bootstrap",
                explanation: "Flutter needs `git` available on PATH and a valid SDK checkout to run any command.",
                suggestion: "Make sure Xcode Command Line Tools are installed (`xcode-select --install`) and that your Flutter SDK directory is intact."
            )
        ),
        Rule(
            patterns: [
                "Working directory does not exist"
            ],
            diagnosis: Diagnosis(
                title: "Project folder moved or deleted",
                explanation: "launchpilot tried to run a command inside the project folder, but the path no longer exists.",
                suggestion: "Re-add the project from the Projects screen, or restore the folder to its original location."
            )
        ),
        Rule(
            patterns: [
                "fastlane: command not found",
                "altool: error",
                "asset validation failed"
            ],
            diagnosis: Diagnosis(
                title: "App Store upload failed",
                explanation: "The IPA reached Apple but was rejected during validation, or the upload tool isn't available.",
                suggestion: "Open the failed step's logs and look for the validation reason (bundle ID mismatch, missing icon sizes, version conflicts), then fix and retry."
            )
        )
    ]
}
