import SwiftUI
import AppKit

struct AndroidSigningSnippet: View {
    @State private var copied = false

    private static let snippet = """
    // app/build.gradle  — paste once into your release signing config
    android {
        signingConfigs {
            release {
                if (project.hasProperty('LP_KEYSTORE_FILE')) {
                    storeFile file(project.LP_KEYSTORE_FILE)
                    storePassword project.LP_KEYSTORE_PASSWORD
                    keyAlias project.LP_KEY_ALIAS
                    keyPassword project.LP_KEY_PASSWORD
                }
            }
        }
        buildTypes {
            release {
                signingConfig signingConfigs.release
            }
        }
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("One-time setup")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.snippet, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy snippet", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("launchpilot passes signing details as `-P` properties at build time. Your `app/build.gradle` needs to read them from the project.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                Text(Self.snippet)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
    }
}
