# launchpilot — Project Specification

> Open-source native macOS app for building, signing, archiving, and publishing mobile apps with a clean GUI and editable project configuration.

---

## 1. Product Vision

launchpilot is a native macOS desktop application that makes mobile app releases simple.

The user selects a project folder, launchpilot detects the framework, creates or updates a project config file, validates the local environment, builds the app, signs it, archives it, and optionally publishes it to Apple App Store, TestFlight, or Google Play Store.

The experience should feel like:

> Select project → Detect stack → Configure once → Build → Archive → Publish

The app must be powerful enough for developers, but simple enough for freelancers, agencies, indie makers, and non-DevOps users.

---

## 2. Core Principles

1. **Local-first by default**  
   Builds should run on the user’s Mac using local Xcode, Android SDK, Flutter, Expo, Gradle, and related CLI tools.

2. **Hybrid-ready architecture**  
   The system should be designed so cloud builds can be added later, but cloud build support is not required in the initial version.

3. **No login required**  
   The MVP should work fully offline without user accounts.

4. **Config-driven**  
   Every project should have a project-level config file that can be committed to Git.

5. **Secrets never go into Git**  
   Credentials, API keys, certificates, and tokens must be stored securely in macOS Keychain or encrypted local storage.

6. **Apple-like UI**  
   Native, calm, clean, minimal, polished, and easy to understand.

7. **Open source**  
   The app should be useful as an open-source developer tool.

---

## 3. MVP Framework Support

launchpilot should support these project types:

1. Flutter
2. Expo
3. React Native CLI
4. Native iOS
5. Native Android

Framework detection should happen automatically when the user selects a project folder.

---

## 4. Supported Release Targets

Initial release targets:

1. Apple App Store
2. TestFlight
3. Google Play Store
4. Archive build only

Archive build means launchpilot creates the final build artifact without publishing it.

Expected artifacts:

- iOS: `.xcarchive`, `.ipa`
- Android: `.aab`, optionally `.apk`

---

## 5. Desktop Technology Stack

Use native macOS technologies.

Recommended stack:

- Swift
- SwiftUI
- Combine or Swift Concurrency
- Foundation
- AppKit only where required
- Keychain Services
- SQLite for local app data if needed
- Codable for config parsing
- Process API for running CLI commands

Do not use Electron, Tauri, Flutter Desktop, or web wrappers for the main app.

---

## 6. High-Level Architecture

```txt
launchpilot macOS App
├── UI Layer - SwiftUI
├── Project Manager
├── Framework Detector
├── Config Manager
├── Environment Validator
├── Credential Manager
├── Build Engine
├── Release Manager
├── Publisher Integrations
├── Log Engine
├── Artifact Manager
└── Optional AI Assistant Layer - later
```

---

## 7. Suggested Folder Structure

```txt
launchpilot/
├── launchpilotApp.swift
├── App/
│   ├── AppState.swift
│   ├── AppRouter.swift
│   └── AppConstants.swift
├── UI/
│   ├── Dashboard/
│   ├── Projects/
│   ├── ProjectDetail/
│   ├── Build/
│   ├── Releases/
│   ├── Credentials/
│   ├── Settings/
│   └── Components/
├── Core/
│   ├── Models/
│   ├── Detection/
│   ├── Config/
│   ├── Environment/
│   ├── Credentials/
│   ├── BuildEngine/
│   ├── Publishing/
│   ├── Logs/
│   ├── Artifacts/
│   └── Utilities/
├── Integrations/
│   ├── Apple/
│   ├── GooglePlay/
│   ├── Flutter/
│   ├── Expo/
│   ├── ReactNative/
│   ├── NativeIOS/
│   └── NativeAndroid/
├── Storage/
│   ├── LocalDatabase.swift
│   ├── KeychainStore.swift
│   └── PreferencesStore.swift
└── Resources/
```

---

## 8. Project Config File

Use YAML instead of JSON.

Reason: YAML is easier for humans to edit, cleaner for release workflows, and common in CI/CD tooling.

Config file name:

```txt
launchpilot.yaml
```

The config file should live in the project root and should be safe to commit to Git.

### Example `launchpilot.yaml`

```yaml
version: 1

project:
  name: Prism Mobile
  framework: flutter
  root: .

apps:
  ios:
    enabled: true
    bundle_id: org.prismonline.mobile
    scheme: Runner
    workspace: ios/Runner.xcworkspace
    configuration: Release
    export_method: app-store
    team_id: ABCDE12345
    signing:
      mode: automatic
      provisioning_profile_name: null
    build:
      output_dir: build/ios
      archive_path: build/ios/archive/Prism.xcarchive
      ipa_output_dir: build/ios/ipa

  android:
    enabled: true
    package_name: org.prismonline.mobile
    module: app
    build_type: release
    flavor: null
    artifact_type: aab
    signing:
      keystore_ref: prism_android_keystore
    build:
      output_dir: build/android

environments:
  production:
    display_name: Production
    ios:
      bundle_id: org.prismonline.mobile
      export_method: app-store
    android:
      package_name: org.prismonline.mobile
      track: production

  beta:
    display_name: Beta
    ios:
      bundle_id: org.prismonline.mobile
      export_method: app-store
      destination: testflight
    android:
      package_name: org.prismonline.mobile
      track: internal

commands:
  prebuild: []
  postbuild: []

publishing:
  apple:
    enabled: true
    api_key_ref: apple_app_store_connect_key
    app_id: null

  google_play:
    enabled: true
    service_account_ref: google_play_service_account
    default_track: internal

artifacts:
  keep_last: 10
  open_after_build: true

advanced:
  parallel_builds: true
  verbose_logs: true
```

---

## 9. Secret Storage

Secrets must not be stored inside `launchpilot.yaml`.

Store secrets in macOS Keychain by default.

Use Keychain for:

- Apple App Store Connect API key
- Apple issuer ID
- Apple key ID
- Google Play service account JSON
- Android keystore password
- Android key alias
- Android key password
- OpenAI API key
- Other LLM provider keys

Recommended approach:

```txt
launchpilot.yaml stores only references.
macOS Keychain stores actual secret values.
```

Example:

```yaml
publishing:
  apple:
    api_key_ref: apple_app_store_connect_key
```

The app resolves `apple_app_store_connect_key` from Keychain.

If encrypted local DB is used later, use it only for non-Keychain-friendly structured secret metadata. Actual secret values should still prefer Keychain.

---

## 10. Local App Storage

launchpilot needs local storage for managing projects and history.

Suggested local storage:

- SQLite for structured local data
- UserDefaults for simple preferences
- Keychain for secrets

Local database can store:

- Project list
- Project paths
- Last opened date
- Build history
- Artifact metadata
- Release history
- Non-secret settings
- Log references

Do not store secrets in SQLite unless encrypted.

---

## 11. Framework Detection

When the user selects a source folder, detect the framework using file patterns.

### Flutter

Detect when:

```txt
pubspec.yaml exists
android/ exists
ios/ exists
```

Useful commands:

```bash
flutter --version
flutter pub get
flutter build ipa
flutter build appbundle
```

### Expo

Detect when:

```txt
app.json exists OR app.config.js exists OR app.config.ts exists
package.json contains expo
```

Useful commands:

```bash
npx expo config
npx expo prebuild
npx eas build
```

For MVP local-first behavior, Expo projects may need prebuild/native directories before local native builds.

### React Native CLI

Detect when:

```txt
package.json contains react-native
android/ exists
ios/ exists
```

Useful commands:

```bash
npm install
cd ios && pod install
xcodebuild ...
./gradlew bundleRelease
```

### Native iOS

Detect when:

```txt
.xcodeproj or .xcworkspace exists
```

Useful commands:

```bash
xcodebuild -list
xcodebuild archive
xcodebuild -exportArchive
```

### Native Android

Detect when:

```txt
settings.gradle or settings.gradle.kts exists
build.gradle or build.gradle.kts exists
```

Useful commands:

```bash
./gradlew tasks
./gradlew bundleRelease
./gradlew assembleRelease
```

---

## 12. Environment Validator

Before building, launchpilot should validate the local environment.

Check for:

### Common

- Git installed
- Project folder readable
- Required config file exists or can be created
- Sufficient disk space
- Internet availability when publishing

### iOS

- macOS version
- Xcode installed
- Xcode command line tools selected
- `xcodebuild` available
- Apple Developer team selected
- Valid signing setup
- Bundle ID configured
- Provisioning profile available
- Required entitlements supported

### Android

- Java installed
- Android SDK installed
- Gradle available
- Android build tools available
- Keystore configured for release builds
- Package name configured

### Flutter

- Flutter installed
- Flutter doctor status
- CocoaPods installed for iOS

### Expo / React Native

- Node.js installed
- npm/yarn/pnpm detected
- CocoaPods installed for iOS
- Native folders available when required

---

## 13. Build Engine

The Build Engine should run CLI commands safely and stream logs in real time.

Required capabilities:

- Run shell commands with controlled working directory
- Stream stdout and stderr live
- Save logs per build
- Support cancellation
- Support parallel builds
- Track command status
- Track duration
- Detect common errors
- Store artifact paths

### Build Job Model

```swift
struct BuildJob {
    let id: UUID
    let projectId: UUID
    let platform: Platform
    let environment: BuildEnvironment
    let action: BuildAction
    var status: BuildStatus
    var startedAt: Date?
    var completedAt: Date?
    var commands: [BuildCommand]
    var artifacts: [BuildArtifact]
}
```

### Build Actions

```txt
archive_only
build_ios_ipa
build_android_aab
publish_testflight
publish_app_store
publish_google_play
```

---

## 14. iOS Build Workflow

For iOS builds, launchpilot should support native Xcode build flow.

General process:

1. Detect workspace/project
2. Detect schemes
3. Select scheme
4. Select configuration
5. Validate signing
6. Run archive command
7. Export IPA
8. Store artifact
9. Optionally upload to TestFlight/App Store

Example archive command:

```bash
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/ios/archive/App.xcarchive \
  -allowProvisioningUpdates
```

Example export command:

```bash
xcodebuild -exportArchive \
  -archivePath build/ios/archive/App.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ExportOptions.plist
```

---

## 15. Apple Publishing Workflow

Use App Store Connect API where possible.

For upload, launchpilot can use Apple tooling underneath:

- `xcrun altool` where applicable
- `xcrun notarytool` if needed later for macOS apps
- Transporter CLI if available
- App Store Connect API for metadata/status where useful

Initial MVP should focus on uploading IPA to TestFlight/App Store processing.

Required Apple credentials:

- App Store Connect API key `.p8`
- Key ID
- Issuer ID
- Team ID

Credential values should be stored in Keychain.

---

## 16. Android Build Workflow

For Android builds:

1. Detect Gradle project
2. Detect modules
3. Detect flavors/build types
4. Validate signing config
5. Run Gradle bundle command
6. Store `.aab`
7. Optionally upload to Play Console

Example command:

```bash
./gradlew :app:bundleRelease
```

For flavored builds:

```bash
./gradlew :app:bundleProductionRelease
```

---

## 17. Google Play Publishing Workflow

Use Google Play Developer API.

Required credential:

- Google Play service account JSON

Store the JSON securely in Keychain.

Publishing targets:

- internal
- alpha
- beta
- production

Initial MVP should support upload to a selected track.

---

## 18. Release Environments

launchpilot should support multiple release environments per project.

Examples:

- production
- beta
- staging
- internal

Each environment can override:

- iOS bundle ID
- Android package name
- Apple export method
- Google Play track
- build flavor
- build configuration
- custom commands

---

## 19. Config Editing UX

The GUI should read and write `launchpilot.yaml`.

User should be able to edit:

- Project name
- Framework
- iOS settings
- Android settings
- Build commands
- Environments
- Publishing options
- Artifact settings
- Parallel build toggle

The GUI must not break manually edited YAML.

Recommended behavior:

- Parse config
- Validate schema
- Show warnings for unknown fields but preserve them where possible
- Save changes safely
- Create backup before rewriting config

---

## 20. Main App Screens

### 20.1 Welcome Screen

Actions:

- Open existing project
- Add project folder
- Recent projects

### 20.2 Dashboard

Show:

- Projects list
- Last build status
- Quick build buttons
- Recent artifacts

### 20.3 Project Detail

Show:

- Framework detected
- Platforms enabled
- Environments
- Build health
- Signing status
- Last release

### 20.4 Configuration Screen

Sections:

- General
- iOS
- Android
- Environments
- Commands
- Publishing
- Artifacts

### 20.5 Credentials Screen

Show references only, not secret values.

Actions:

- Add Apple API key
- Add Google Play service account
- Add Android keystore
- Add LLM API key later
- Test credential
- Delete credential

### 20.6 Build Screen

Show:

- Selected platform
- Selected environment
- Build action
- Live logs
- Current step
- Progress timeline
- Cancel button

### 20.7 Releases Screen

Show:

- Build history
- Artifacts
- Release target
- Upload status
- Version/build number
- Open artifact location

### 20.8 Settings Screen

Show:

- Default shell
- Preferred package manager
- Log retention
- Artifact retention
- LLM provider settings later
- OpenAI API key reference later

---

## 21. Parallel Build Support

launchpilot should support parallel builds where safe.

Examples:

- Build iOS and Android at the same time
- Build multiple projects if the user starts them

Need safeguards:

- Limit max concurrent jobs
- Avoid running conflicting commands in same project folder
- Prevent two builds writing to same output path
- Show clear status per job

---

## 22. Auto Screenshot Feature

Future advanced feature.

Purpose:

- Generate or capture screenshots for store submissions
- Help users prepare store assets

Possible approaches:

### iOS

- Use simulator
- Install app
- Launch app
- Capture screenshots with `xcrun simctl io booted screenshot`

### Android

- Use emulator
- Install APK
- Launch app
- Capture screenshots with `adb exec-out screencap`

This can be added after core build/publish workflows are stable.

---

## 23. Optional AI Features

AI is not part of MVP, but the architecture should allow it later.

Settings should later allow users to configure:

- OpenAI API key
- Model name
- Optional custom endpoint

AI features later:

- Explain build errors
- Suggest fixes
- Generate release notes
- Generate store description
- Detect config problems
- Summarize logs
- Warn about App Store / Play Store review risks

Secrets for AI providers must be stored in Keychain.

---

## 24. Error Diagnosis System

Even before AI, launchpilot should include rule-based error detection.

Example rules:

### iOS Push Notification Entitlement Error

Detect log patterns:

```txt
Provisioning profile doesn't support the Push Notifications capability
Provisioning profile doesn't include the aps-environment entitlement
```

Show user-friendly explanation:

```txt
Your app is requesting Push Notifications, but the selected provisioning profile was created without Push Notifications enabled. Enable Push Notifications for your App ID in Apple Developer, then regenerate the provisioning profile.
```

### Android Keystore Error

Detect:

```txt
Keystore was tampered with, or password was incorrect
```

Show:

```txt
The Android keystore password or key password is incorrect. Update the stored keystore credentials in launchpilot Credentials.
```

---

## 25. Logging

launchpilot should provide excellent logs.

Requirements:

- Stream logs live
- Store logs per build
- Search logs
- Copy logs
- Export logs
- Highlight warnings/errors
- Show command that failed
- Show exit code

Log storage path example:

```txt
~/Library/Application Support/launchpilot/logs/{projectId}/{buildId}.log
```

---

## 26. Artifact Management

Artifacts should be stored and indexed.

Default artifact path:

```txt
~/Library/Application Support/launchpilot/artifacts/{projectId}/{buildId}/
```

Each artifact should store:

- Name
- Type
- Platform
- Path
- Size
- Created date
- Build ID
- Environment

User actions:

- Reveal in Finder
- Copy path
- Delete artifact
- Upload/publish artifact

---

## 27. Open Source Repository Structure

Recommended repo structure:

```txt
launchpilot/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── SECURITY.md
├── docs/
│   ├── architecture.md
│   ├── config-reference.md
│   ├── framework-detection.md
│   ├── publishing-apple.md
│   └── publishing-google-play.md
├── app/
│   └── launchpilot/
├── examples/
│   ├── flutter-launchpilot.yaml
│   ├── expo-launchpilot.yaml
│   ├── react-native-launchpilot.yaml
│   ├── native-ios-launchpilot.yaml
│   └── native-android-launchpilot.yaml
└── scripts/
```

---

## 28. MVP Scope

The first MVP should focus on being useful and stable, not covering everything perfectly.

### MVP Must Have

- Native SwiftUI macOS app
- Add/select project folder
- Auto-detect framework
- Create `launchpilot.yaml`
- Read/update `launchpilot.yaml`
- Multi-project dashboard
- Environment validation
- Basic credential storage in Keychain
- iOS archive build
- Android AAB build
- Flutter build support
- React Native CLI build support
- Native iOS build support
- Native Android build support
- Expo detection with guidance for local/native build requirements
- Archive-only build
- Live logs
- Build history
- Artifact management

### MVP Should Have

- TestFlight upload
- Google Play internal track upload
- Rule-based error diagnosis
- Parallel iOS + Android builds

### Not Required in MVP

- User auth
- Backend
- Cloud build
- AI features
- Auto screenshots
- Team collaboration
- Store metadata management
- Paid subscription

---

## 29. Implementation Phases

### Phase 1 — Foundation

- Create SwiftUI app shell
- Project picker
- Recent projects
- Local database
- Keychain wrapper
- Basic settings

### Phase 2 — Detection + Config

- Framework detector
- Config schema
- YAML parser/writer
- Config editor UI
- Validation messages

### Phase 3 — Build Engine

- Process runner
- Live logs
- Build jobs
- Cancellation
- Artifact detection
- Build history

### Phase 4 — iOS Build Support

- Xcode project/workspace detection
- Scheme detection
- Archive command generation
- Export options plist generation
- IPA export
- Signing validation

### Phase 5 — Android Build Support

- Gradle project detection
- Module/flavor detection
- AAB/APK build command generation
- Keystore validation

### Phase 6 — Framework-Specific Support

- Flutter commands
- React Native commands
- Expo project guidance
- Native iOS presets
- Native Android presets

### Phase 7 — Publishing

- App Store Connect credential setup
- TestFlight upload
- Google Play service account setup
- Google Play internal/beta/production track upload

### Phase 8 — Polish

- Apple-like UI refinement
- Error diagnosis rules
- Build timeline UI
- Better logs
- Artifact cleanup
- Documentation

### Phase 9 — Advanced Features

- Parallel builds
- Auto screenshots
- LLM settings
- AI log explanation
- Store metadata management
- Cloud build architecture

---

## 30. Important UX Details

The app should always explain problems in simple language.

Bad:

```txt
xcodebuild exited with status 65
```

Good:

```txt
Xcode failed during archive. The most likely reason is signing or provisioning. Open the signing checklist below to fix it.
```

The UI should avoid overwhelming users with raw DevOps concepts first. Show simple status, then allow advanced details.

---

## 31. Design Direction

Style:

- Native Apple-like macOS UI
- Clean sidebar
- Soft cards
- Clear build status indicators
- Minimal icons
- Large readable logs
- No clutter
- No heavy gradients
- Calm professional feeling

Suggested navigation:

```txt
Sidebar
├── Projects
├── Builds
├── Releases
├── Credentials
└── Settings
```

---

## 32. Security Rules

1. Never write secrets to `launchpilot.yaml`.
2. Never print secrets in logs.
3. Mask secrets in UI.
4. Store secrets in Keychain.
5. Ask confirmation before deleting credentials.
6. Warn before publishing to production.
7. Make archive-only the safest default action.
8. Do not upload project source code anywhere in MVP.

---

## 33. Naming

Working name:

```txt
launchpilot
```

Tagline ideas:

```txt
Build. Sign. Ship.
```

```txt
Mobile releases made simple.
```

```txt
The easiest way to build and publish mobile apps.
```

---

## 34. Success Criteria

launchpilot is successful when a user can:

1. Open a Flutter, React Native, native iOS, or native Android project.
2. Let launchpilot detect the project type.
3. Generate a clean `launchpilot.yaml`.
4. Configure iOS and Android release settings through GUI.
5. Store secrets securely outside Git.
6. Build an iOS archive or Android AAB.
7. View logs and artifacts.
8. Upload to TestFlight or Google Play with minimal CLI knowledge.

---

## 35. Instructions for AI Agent Building This Project

Build this as a production-quality native macOS SwiftUI app.

Prioritize:

1. Clean architecture
2. Safe secret handling
3. Reliable process execution
4. Excellent logs
5. Config-driven workflows
6. Simple Apple-like UX
7. Extensible framework adapters

Do not hardcode one framework deeply into the app. Use adapter/protocol-based design so each framework can implement detection, validation, build, archive, and publish behavior independently.

Suggested protocol:

```swift
protocol FrameworkAdapter {
    var id: String { get }
    var displayName: String { get }

    func detect(at path: URL) async -> DetectionResult
    func validate(project: ProjectConfig) async -> [ValidationIssue]
    func generateDefaultConfig(for path: URL) async throws -> ProjectConfig
    func build(job: BuildJob, config: ProjectConfig) async throws -> BuildResult
}
```

Suggested publisher protocol:

```swift
protocol PublisherAdapter {
    var id: String { get }
    var displayName: String { get }

    func validateCredentials(ref: String) async -> [ValidationIssue]
    func publish(artifact: BuildArtifact, config: ProjectConfig, environment: String) async throws -> PublishResult
}
```

Keep the system modular from the beginning.
