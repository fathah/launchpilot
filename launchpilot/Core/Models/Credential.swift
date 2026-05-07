import Foundation

enum CredentialKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleAPIKey = "apple_api_key"
    case googlePlayServiceAccount = "google_play_service_account"
    case androidKeystore = "android_keystore"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleAPIKey: return "Apple App Store Connect Key"
        case .googlePlayServiceAccount: return "Google Play Service Account"
        case .androidKeystore: return "Android Keystore"
        }
    }

    var shortName: String {
        switch self {
        case .appleAPIKey: return "Apple API Key"
        case .googlePlayServiceAccount: return "Google Play Service Account"
        case .androidKeystore: return "Android Keystore"
        }
    }

    var symbolName: String {
        switch self {
        case .appleAPIKey: return "applelogo"
        case .googlePlayServiceAccount: return "play.rectangle.fill"
        case .androidKeystore: return "lock.shield.fill"
        }
    }
}

struct AppleAPIKeySecret: Codable, Hashable, Sendable {
    var keyId: String
    var issuerId: String
    var teamId: String?
    var p8Contents: String
}

struct GooglePlayServiceAccountSecret: Codable, Hashable, Sendable {
    var jsonContents: String
    var clientEmail: String?
}

struct AndroidKeystoreSecret: Codable, Hashable, Sendable {
    var keystorePath: String
    var keystorePassword: String
    var keyAlias: String
    var keyPassword: String
}

enum CredentialSecret: Codable, Hashable, Sendable {
    case appleAPIKey(AppleAPIKeySecret)
    case googlePlayServiceAccount(GooglePlayServiceAccountSecret)
    case androidKeystore(AndroidKeystoreSecret)

    var kind: CredentialKind {
        switch self {
        case .appleAPIKey: return .appleAPIKey
        case .googlePlayServiceAccount: return .googlePlayServiceAccount
        case .androidKeystore: return .androidKeystore
        }
    }
}

struct Credential: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var ref: String
    var displayName: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var secret: CredentialSecret

    var kind: CredentialKind { secret.kind }

    init(
        id: UUID = UUID(),
        ref: String,
        displayName: String,
        notes: String? = nil,
        secret: CredentialSecret,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ref = ref
        self.displayName = displayName
        self.notes = notes
        self.secret = secret
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
