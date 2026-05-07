<p align="center">
<img width="300"  alt="launchpilot-h" src="https://github.com/user-attachments/assets/d6ed907e-36e8-469b-b936-30710df10de5" />
</p>

<b>
<p align="center">
  A native macOS app for building, signing, archiving, and publishing mobile apps with a clean GUI and editable project configuration.
</p>
</b>

launchpilot makes mobile app releases simple. Point it at a project folder, and it detects the framework, manages your config, validates the local environment, builds, signs, archives, and optionally publishes to the App Store, TestFlight, or Google Play.

```
Select project → Detect stack → Configure once → Build → Archive → Publish
```

## Features

- **Native macOS app** built with SwiftUI — no Electron, no web wrappers
- **Local-first** — runs builds on your Mac using local toolchains
- **No login required** — works fully offline
- **Auto framework detection** for Flutter, Expo, React Native CLI, native iOS, and native Android
- **Config-driven** via a Git-friendly `launchpilot.yaml` file
- **Secrets stay safe** in macOS Keychain — never in Git
- **Live build logs** with cancellation, history, and artifact tracking
- **Multi-environment** support (production, beta, staging, internal)
- **Parallel builds** for iOS and Android

## Supported Frameworks

| Framework | Detection | Status |
|-----------|-----------|--------|
| Flutter | `pubspec.yaml` + `ios/` + `android/` | MVP |
| Expo | `app.json` / `app.config.*` + `expo` in `package.json` | MVP |
| React Native CLI | `react-native` in `package.json` + native dirs | MVP |
| Native iOS | `.xcodeproj` / `.xcworkspace` | MVP |
| Native Android | `settings.gradle` / `build.gradle` | MVP |

## Release Targets

- Apple App Store
- TestFlight
- Google Play (internal, alpha, beta, production)
- Archive-only (build artifact without publishing)

Output artifacts: `.xcarchive`, `.ipa`, `.aab`, `.apk`.

## Requirements

- macOS (Apple Silicon or Intel)
- Xcode 15+ (for iOS builds)
- Android SDK + JDK (for Android builds)
- Framework toolchains as needed: Flutter, Node.js + npm/yarn/pnpm, CocoaPods

launchpilot's environment validator will check for missing dependencies before each build.

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-org>/launchpilot.git
   cd launchpilot
   ```
2. Open `launchpilot.xcodeproj` in Xcode.
3. Build and run the `launchpilot` scheme.
4. In the app, click **Add Project** and select a mobile project folder. launchpilot detects the framework and offers to create a `launchpilot.yaml`.

## Project Configuration

Each project gets a `launchpilot.yaml` at its root. It is safe to commit to Git and stores no secrets — only Keychain references.

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
  android:
    enabled: true
    package_name: org.prismonline.mobile
    artifact_type: aab
    signing:
      keystore_ref: prism_android_keystore

environments:
  production:
    ios: { export_method: app-store }
    android: { track: production }
  beta:
    ios: { destination: testflight }
    android: { track: internal }

publishing:
  apple:
    enabled: true
    api_key_ref: apple_app_store_connect_key
  google_play:
    enabled: true
    service_account_ref: google_play_service_account
    default_track: internal
```

See [PROJECT.md](PROJECT.md) for the full schema.

## Architecture

```
launchpilot macOS App
├── UI Layer (SwiftUI)
├── Project Manager
├── Framework Detector
├── Config Manager (YAML)
├── Environment Validator
├── Credential Manager (Keychain)
├── Build Engine (Process API + live logs)
├── Release Manager
├── Publisher Integrations (Apple, Google Play)
├── Log Engine
└── Artifact Manager
```

Frameworks and publishers are implemented as adapters behind `FrameworkAdapter` and `PublisherAdapter` protocols, so new platforms can be added without touching core logic.

## Storage Locations

- Logs: `~/Library/Application Support/launchpilot/logs/{projectId}/{buildId}.log`
- Artifacts: `~/Library/Application Support/launchpilot/artifacts/{projectId}/{buildId}/`
- Secrets: macOS Keychain
- Project metadata: local SQLite

## Security

- Secrets are never written to `launchpilot.yaml`
- Secrets are masked in the UI and never printed in logs
- Archive-only is the safest default action
- Production publishes require explicit confirmation
- Source code is never uploaded anywhere

## Roadmap

- ✅ Phase 1 — App shell, project picker, local DB, Keychain wrapper
- 🚧 Phase 2 — Framework detection + YAML config editor
- ⏳ Phase 3 — Build engine with live logs
- ⏳ Phase 4–5 — iOS and Android build support
- ⏳ Phase 6 — Framework-specific adapters
- ⏳ Phase 7 — TestFlight and Google Play publishing
- ⏳ Phase 8 — Error diagnosis, polish, docs
- ⏳ Phase 9 — Parallel builds, auto screenshots, optional AI features

See [PROJECT.md](PROJECT.md) for the detailed phase breakdown.

## Contributing

Contributions are welcome. The project follows an adapter-based architecture so each framework or publisher can be developed independently. Please read the project specification in [PROJECT.md](PROJECT.md) before opening a PR.

## License

To be added.
