import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Application Support") {
                    Text(AppConstants.applicationSupportDirectory.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Logs directory") {
                    Text(AppConstants.logsDirectory.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Artifacts directory") {
                    Text(AppConstants.artifactsDirectory.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            }

            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
