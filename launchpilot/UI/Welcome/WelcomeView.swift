import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)

                Text("Welcome to launchpilot")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))

                Text("Build, sign, and ship mobile apps from your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await appState.addProjectFromPicker() }
                } label: {
                    Label("Add Project Folder", systemImage: "folder.badge.plus")
                        .frame(minWidth: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Text("launchpilot will detect Flutter, Expo, React Native, native iOS, or native Android automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Spacer()

            Text("Open source · Local first · No login required")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
