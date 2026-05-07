import SwiftUI
import AppKit

enum CredentialEditorMode: Identifiable {
    case create(kind: CredentialKind)
    case edit(credential: Credential)

    var id: String {
        switch self {
        case .create(let kind): return "create-\(kind.rawValue)"
        case .edit(let credential): return "edit-\(credential.id.uuidString)"
        }
    }

    var kind: CredentialKind {
        switch self {
        case .create(let kind): return kind
        case .edit(let credential): return credential.kind
        }
    }
}

struct CredentialEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: CredentialEditorMode

    @State private var ref: String = ""
    @State private var refWasEdited: Bool = false
    @State private var originalRef: String = ""
    @State private var displayName: String = ""
    @State private var notes: String = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showAdvanced: Bool = false

    @State private var apple = AppleAPIKeyForm()
    @State private var google = GooglePlayForm()
    @State private var keystore = KeystoreForm()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introCard
                    nameStep
                    Divider()
                    kindSpecificFields
                    Divider()
                    advancedSection
                    if let error = saveError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { primeFields() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.kind.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCreating ? "Add \(mode.kind.shortName)" : "Edit \(mode.kind.shortName)")
                    .font(.headline)
                Text("Saved to your Mac's Keychain. Nothing leaves your machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
                .font(.body)
            Text(introText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var introText: String {
        switch mode.kind {
        case .appleAPIKey:
            return "An Apple API Key lets launchpilot upload your iOS app to the App Store on your behalf. You'll get this from App Store Connect — it's a one-time setup."
        case .googlePlayServiceAccount:
            return "A Google Play service account lets launchpilot upload your Android app to the Play Store. You'll create one in Google Cloud Console and link it inside Play Console."
        case .androidKeystore:
            return "A keystore is the digital signature for your Android app. Google Play requires that every release be signed with the same keystore — keep this file safe!"
        }
    }

    private var nameStep: some View {
        StepRow(number: 1, title: "Name this credential") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("e.g. Production Apple Key", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: displayName) { _, newValue in
                        if !refWasEdited { ref = slugify(newValue) }
                    }
                Text("A friendly name so you can recognize it later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var kindSpecificFields: some View {
        switch mode.kind {
        case .appleAPIKey:
            AppleAPIKeySection(form: $apple)
        case .googlePlayServiceAccount:
            GooglePlaySection(form: $google)
        case .androidKeystore:
            KeystoreSection(form: $keystore)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Reference name (YAML)")
                            .font(.subheadline.weight(.medium))
                        HelpPopoverButton(
                            title: "What is this?",
                            body: "This is the ID that goes into your project's launchpilot.yaml file. It's how the project file points at this credential. Letters, numbers, dot, dash, underscore only.\n\nUnless you have a specific reason to change it, leave the auto-generated value alone."
                        )
                    }
                    TextField("auto_generated_from_name", text: $ref)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: ref) { _, _ in refWasEdited = true }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (optional)")
                        .font(.subheadline.weight(.medium))
                    TextField("Anything you want to remember about this credential", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isCreating ? "Add Credential" : "Save Changes")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var isValid: Bool {
        guard !ref.trimmingCharacters(in: .whitespaces).isEmpty,
              !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode.kind {
        case .appleAPIKey:
            return !apple.keyId.isEmpty && !apple.issuerId.isEmpty && !apple.p8Contents.isEmpty
        case .googlePlayServiceAccount:
            return !google.jsonContents.isEmpty
        case .androidKeystore:
            return !keystore.keystorePath.isEmpty
                && !keystore.keystorePassword.isEmpty
                && !keystore.keyAlias.isEmpty
                && !keystore.keyPassword.isEmpty
        }
    }

    private func primeFields() {
        switch mode {
        case .create:
            ref = ""
            originalRef = ""
            displayName = ""
            notes = ""
            refWasEdited = false
        case .edit(let credential):
            ref = credential.ref
            originalRef = credential.ref
            displayName = credential.displayName
            notes = credential.notes ?? ""
            refWasEdited = true
            showAdvanced = true
            switch credential.secret {
            case .appleAPIKey(let secret):
                apple = AppleAPIKeyForm(
                    keyId: secret.keyId,
                    issuerId: secret.issuerId,
                    teamId: secret.teamId ?? "",
                    p8Contents: secret.p8Contents,
                    p8FileName: ""
                )
            case .googlePlayServiceAccount(let secret):
                google = GooglePlayForm(
                    jsonContents: secret.jsonContents,
                    fileName: "",
                    clientEmail: secret.clientEmail ?? ""
                )
            case .androidKeystore(let secret):
                keystore = KeystoreForm(
                    keystorePath: secret.keystorePath,
                    keystorePassword: secret.keystorePassword,
                    keyAlias: secret.keyAlias,
                    keyPassword: secret.keyPassword
                )
            }
        }
    }

    private func save() {
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        let secret: CredentialSecret
        switch mode.kind {
        case .appleAPIKey:
            secret = .appleAPIKey(AppleAPIKeySecret(
                keyId: apple.keyId.trimmingCharacters(in: .whitespaces),
                issuerId: apple.issuerId.trimmingCharacters(in: .whitespaces),
                teamId: apple.teamId.isEmpty ? nil : apple.teamId.trimmingCharacters(in: .whitespaces),
                p8Contents: apple.p8Contents
            ))
        case .googlePlayServiceAccount:
            secret = .googlePlayServiceAccount(GooglePlayServiceAccountSecret(
                jsonContents: google.jsonContents,
                clientEmail: google.clientEmail.isEmpty ? nil : google.clientEmail
            ))
        case .androidKeystore:
            secret = .androidKeystore(AndroidKeystoreSecret(
                keystorePath: keystore.keystorePath,
                keystorePassword: keystore.keystorePassword,
                keyAlias: keystore.keyAlias,
                keyPassword: keystore.keyPassword
            ))
        }

        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)
        let credential: Credential
        let isNew: Bool
        switch mode {
        case .create:
            credential = Credential(
                ref: trimmedRef,
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                notes: notes.isEmpty ? nil : notes,
                secret: secret
            )
            isNew = true
        case .edit(let existing):
            credential = Credential(
                id: existing.id,
                ref: trimmedRef,
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                notes: notes.isEmpty ? nil : notes,
                secret: secret,
                createdAt: existing.createdAt
            )
            isNew = false
        }

        do {
            try appState.saveCredential(credential, isNew: isNew, originalRef: isNew ? nil : originalRef)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private func slugify(_ input: String) -> String {
    let lowered = input.lowercased()
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-.")
    var result = ""
    var lastWasUnderscore = false
    for ch in lowered {
        if allowed.contains(ch) {
            result.append(ch)
            lastWasUnderscore = (ch == "_")
        } else if ch.isWhitespace || ch.isPunctuation {
            if !lastWasUnderscore && !result.isEmpty {
                result.append("_")
                lastWasUnderscore = true
            }
        }
    }
    while result.hasSuffix("_") { result.removeLast() }
    return result
}

// MARK: - Form models

private struct AppleAPIKeyForm {
    var keyId: String = ""
    var issuerId: String = ""
    var teamId: String = ""
    var p8Contents: String = ""
    var p8FileName: String = ""
}

private struct GooglePlayForm {
    var jsonContents: String = ""
    var fileName: String = ""
    var clientEmail: String = ""
}

private struct KeystoreForm {
    var keystorePath: String = ""
    var keystorePassword: String = ""
    var keyAlias: String = ""
    var keyPassword: String = ""
}

// MARK: - Sections

private struct AppleAPIKeySection: View {
    @Binding var form: AppleAPIKeyForm

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(
                number: 2,
                title: "Upload your .p8 private key",
                help: HelpContent(
                    title: "Where do I get the .p8 file?",
                    bullets: [
                        "Sign in to App Store Connect.",
                        "Click **Users and Access** in the top menu.",
                        "Click the **Integrations** tab, then **App Store Connect API**.",
                        "Click the **+** button to create a new key (or use an existing one).",
                        "Give it a name and choose **Admin** or **App Manager** access.",
                        "Click **Generate** — a `.p8` file will download. **Save it!** You can only download it once.",
                        "Come back here and click **Choose .p8 file…** below."
                    ],
                    link: ("Open App Store Connect", "https://appstoreconnect.apple.com/access/integrations/api")
                )
            ) {
                HStack(spacing: 8) {
                    Button {
                        pickP8()
                    } label: {
                        Label(form.p8Contents.isEmpty ? "Choose .p8 file…" : "Replace .p8 file…", systemImage: "doc.badge.plus")
                    }
                    if !form.p8Contents.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(form.p8FileName.isEmpty ? "Loaded" : form.p8FileName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            StepRow(
                number: 3,
                title: "Key ID",
                help: HelpContent(
                    title: "Where do I find the Key ID?",
                    bullets: [
                        "Open the same **App Store Connect API** page where you downloaded the .p8 file.",
                        "Look at the **Key ID** column in the keys list — it's a 10-character string like `ABC123XYZ4`.",
                        "Copy it and paste below."
                    ],
                    link: ("Open keys list", "https://appstoreconnect.apple.com/access/integrations/api")
                )
            ) {
                TextField("e.g. ABC123XYZ4", text: $form.keyId)
                    .textFieldStyle(.roundedBorder)
            }

            StepRow(
                number: 4,
                title: "Issuer ID",
                help: HelpContent(
                    title: "Where do I find the Issuer ID?",
                    bullets: [
                        "Open the **App Store Connect API** page.",
                        "At the top of the page, you'll see **Issuer ID** with a long UUID like `12345678-1234-1234-1234-123456789012`.",
                        "Click the copy icon next to it and paste below.",
                        "_The Issuer ID is the same for every key in your account._"
                    ],
                    link: ("Open keys list", "https://appstoreconnect.apple.com/access/integrations/api")
                )
            ) {
                TextField("UUID from App Store Connect", text: $form.issuerId)
                    .textFieldStyle(.roundedBorder)
            }

            StepRow(
                number: 5,
                title: "Team ID (optional)",
                help: HelpContent(
                    title: "Where do I find my Team ID?",
                    bullets: [
                        "Sign in to the Apple Developer portal at developer.apple.com.",
                        "Click **Account** → **Membership details**.",
                        "Your **Team ID** is a 10-character string near the top.",
                        "_Only needed if your Apple ID is on multiple teams._"
                    ],
                    link: ("Open Apple Developer", "https://developer.apple.com/account")
                )
            ) {
                TextField("10-character team ID", text: $form.teamId)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func pickP8() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.allowedFileTypes = ["p8"]
        panel.title = "Choose .p8 private key"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            form.p8Contents = text
            form.p8FileName = url.lastPathComponent
        }
    }
}

private struct GooglePlaySection: View {
    @Binding var form: GooglePlayForm

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(
                number: 2,
                title: "Upload your service account JSON",
                help: HelpContent(
                    title: "How do I create a service account?",
                    bullets: [
                        "Open **Google Cloud Console** and select (or create) a project.",
                        "Go to **IAM & Admin** → **Service Accounts** → **Create Service Account**.",
                        "Give it a name like `launchpilot-uploader` and click **Create and Continue**.",
                        "Skip granting roles for now — click **Done**.",
                        "Click the new service account, go to the **Keys** tab → **Add Key** → **Create new key** → **JSON**.",
                        "A `.json` file will download. Come back here and click **Choose JSON file…**.",
                        "**Important:** also open Google **Play Console** → **Users and permissions** → **Invite new users**, paste the service account's email, and grant **Admin (all permissions)** or at minimum **Release manager** access for your apps."
                    ],
                    link: ("Open Google Cloud Console", "https://console.cloud.google.com/iam-admin/serviceaccounts")
                )
            ) {
                HStack(spacing: 8) {
                    Button {
                        pickJSON()
                    } label: {
                        Label(form.jsonContents.isEmpty ? "Choose JSON file…" : "Replace JSON file…", systemImage: "doc.badge.plus")
                    }
                    if !form.jsonContents.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(form.fileName.isEmpty ? "Loaded" : form.fileName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if !form.clientEmail.isEmpty {
                StepRow(number: 3, title: "Service account email (auto-detected)") {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill").foregroundStyle(.secondary)
                        Text(form.clientEmail)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }
    }

    private func pickJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["json"]
        panel.title = "Choose service account JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        form.jsonContents = text
        form.fileName = url.lastPathComponent
        if let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = dict["client_email"] as? String {
            form.clientEmail = email
        }
    }
}

private struct KeystoreSection: View {
    @Binding var form: KeystoreForm

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(
                number: 2,
                title: "Choose your keystore file",
                help: HelpContent(
                    title: "What is a keystore — and what if I don't have one?",
                    bullets: [
                        "A keystore is a `.jks` or `.keystore` file containing the digital signature for your Android app.",
                        "If you've published your app before, you already have one — find it on your computer (often inside your project folder).",
                        "**If this is your first release**, you can create one by running this in Terminal:",
                        "`keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias myapp`",
                        "**Critical:** back this file up somewhere safe (password manager, encrypted drive). If you lose it, you can never update your app on Play Store again — you'd have to publish as a new app.",
                        "launchpilot only stores the path to this file. The keystore itself stays where it is on disk."
                    ],
                    link: nil
                )
            ) {
                HStack(spacing: 8) {
                    Button {
                        pickKeystore()
                    } label: {
                        Label(form.keystorePath.isEmpty ? "Choose keystore…" : "Replace keystore…", systemImage: "doc.badge.plus")
                    }
                    if !form.keystorePath.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(form.keystorePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            StepRow(
                number: 3,
                title: "Keystore password",
                help: HelpContent(
                    title: "What's the keystore password?",
                    bullets: [
                        "This is the password you set when the keystore was first created.",
                        "If you forgot it, there's no recovery — the keystore can't be used.",
                        "Check your password manager or any setup docs from when you published your first release."
                    ],
                    link: nil
                )
            ) {
                SecureField("", text: $form.keystorePassword)
                    .textFieldStyle(.roundedBorder)
            }

            StepRow(
                number: 4,
                title: "Key alias",
                help: HelpContent(
                    title: "What's a key alias?",
                    bullets: [
                        "A keystore can hold multiple keys; the alias is the name of the specific one for your app.",
                        "If you generated the keystore using `keytool`, the alias is the value you passed to `-alias` (e.g. `myapp`).",
                        "To list all aliases inside a keystore, run: `keytool -list -v -keystore yourkeystore.jks`"
                    ],
                    link: nil
                )
            ) {
                TextField("Release key alias", text: $form.keyAlias)
                    .textFieldStyle(.roundedBorder)
            }

            StepRow(
                number: 5,
                title: "Key password",
                help: HelpContent(
                    title: "What's the key password?",
                    bullets: [
                        "Each key inside the keystore has its own password.",
                        "Often this is the same as the keystore password — but not always.",
                        "If you're unsure, try the keystore password first."
                    ],
                    link: nil
                )
            ) {
                SecureField("", text: $form.keyPassword)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func pickKeystore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jks", "keystore"]
        panel.title = "Choose keystore"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        form.keystorePath = url.path
    }
}

// MARK: - Reusable step + help components

private struct HelpContent {
    let title: String
    let bullets: [String]
    let link: (label: String, url: String)?
}

private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    var help: HelpContent? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text("\(number)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let help = help {
                        HelpPopoverButton(title: help.title, bullets: help.bullets, link: help.link)
                    }
                    Spacer(minLength: 0)
                }
                content()
            }
        }
    }
}

private struct HelpPopoverButton: View {
    let title: String
    var prose: String? = nil
    var bullets: [String] = []
    var link: (label: String, url: String)? = nil
    var triggerLabel: String = "Where do I get this?"

    @State private var show: Bool = false

    init(title: String, body: String, triggerLabel: String = "What is this?") {
        self.title = title
        self.prose = body
        self.triggerLabel = triggerLabel
    }

    init(title: String, bullets: [String], link: (label: String, url: String)?) {
        self.title = title
        self.bullets = bullets
        self.link = link
    }

    var body: some View {
        Button {
            show = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                Text(triggerLabel)
            }
            .font(.caption)
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                if let prose = self.prose {
                    Text(.init(prose))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 18, alignment: .trailing)
                                Text(.init(step))
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let link = link, let url = URL(string: link.url) {
                    Divider()
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text(link.label)
                        }
                        .font(.callout.weight(.medium))
                    }
                }
            }
            .padding(16)
            .frame(width: 380)
        }
    }
}
