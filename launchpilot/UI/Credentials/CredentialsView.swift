import SwiftUI

struct CredentialsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introHeader

                if appState.credentials.isEmpty {
                    EmptyCredentialsView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    credentialsList
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Credentials")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(CredentialKind.allCases) { kind in
                        Button {
                            state.editingCredential = nil
                            state.addingCredentialKind = kind
                        } label: {
                            Label(kind.shortName, systemImage: kind.symbolName)
                        }
                    }
                } label: {
                    Label("Add credential", systemImage: "plus")
                }
            }
        }
        .sheet(item: $state.addingCredentialKind) { kind in
            CredentialEditorSheet(mode: .create(kind: kind))
        }
        .sheet(item: $state.editingCredential) { credential in
            CredentialEditorSheet(mode: .edit(credential: credential))
        }
    }

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stored in macOS Keychain")
                .font(.headline)
            Text("Reference these credentials by name in launchpilot.yaml. Secrets never leave Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsList: some View {
        VStack(spacing: 8) {
            ForEach(appState.credentials) { credential in
                CredentialRow(credential: credential)
            }
        }
    }
}

private struct EmptyCredentialsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No credentials yet")
                .font(.title3.weight(.semibold))
            Text("Add an Apple App Store Connect API key, Google Play service account, or Android keystore. They're saved to Keychain — only references go into launchpilot.yaml.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }
}

private struct CredentialRow: View {
    @Environment(AppState.self) private var appState
    let credential: Credential

    @State private var showDeleteConfirm = false

    var body: some View {
        Button {
            appState.editingCredential = credential
        } label: {
            HStack(spacing: 12) {
                Image(systemName: credential.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(credential.displayName)
                            .font(.headline)
                        KindBadge(kind: credential.kind)
                    }
                    HStack(spacing: 6) {
                        Text(credential.ref)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("updated \(credential.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit…") { appState.editingCredential = credential }
                    Divider()
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 36)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .alert("Delete credential?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { appState.deleteCredential(credential) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(credential.displayName)\" will be removed from Keychain. Any project referencing \(credential.ref) will need an update.")
        }
    }
}

private struct KindBadge: View {
    let kind: CredentialKind

    var body: some View {
        Text(kind.shortName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch kind {
        case .appleAPIKey: return .gray
        case .googlePlayServiceAccount: return .green
        case .androidKeystore: return .orange
        }
    }
}
