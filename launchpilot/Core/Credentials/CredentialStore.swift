import Foundation

enum CredentialStoreError: Error, LocalizedError {
    case duplicateRef(String)
    case invalidRef(String)

    var errorDescription: String? {
        switch self {
        case .duplicateRef(let ref):
            return "A credential with the reference '\(ref)' already exists."
        case .invalidRef(let ref):
            return "'\(ref)' is not a valid reference. Use letters, numbers, dashes, and underscores."
        }
    }
}

nonisolated struct CredentialStore {
    let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore(service: AppConstants.bundleIdentifier + ".credentials")) {
        self.keychain = keychain
    }

    private static let refPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,64}$")

    static func validate(ref: String) throws {
        let range = NSRange(ref.startIndex..., in: ref)
        guard refPattern.firstMatch(in: ref, range: range) != nil else {
            throw CredentialStoreError.invalidRef(ref)
        }
    }

    func list() -> [Credential] {
        let refs = (try? keychain.listRefs()) ?? []
        let credentials = refs.compactMap { ref -> Credential? in
            try? read(ref: ref)
        }
        return credentials.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    func read(ref: String) throws -> Credential? {
        guard let data = try keychain.data(for: ref) else { return nil }
        return try decode(data)
    }

    func save(_ credential: Credential, isNew: Bool) throws {
        try Self.validate(ref: credential.ref)
        if isNew, try keychain.data(for: credential.ref) != nil {
            throw CredentialStoreError.duplicateRef(credential.ref)
        }
        var copy = credential
        copy.updatedAt = Date()
        let data = try encode(copy)
        try keychain.setData(data, for: credential.ref)
    }

    func rename(from old: String, to new: String) throws {
        try Self.validate(ref: new)
        guard old != new else { return }
        guard var existing = try read(ref: old) else { return }
        if try keychain.data(for: new) != nil {
            throw CredentialStoreError.duplicateRef(new)
        }
        existing.ref = new
        existing.updatedAt = Date()
        try keychain.setData(try encode(existing), for: new)
        try keychain.delete(ref: old)
    }

    func delete(ref: String) throws {
        try keychain.delete(ref: ref)
    }

    private func encode(_ credential: Credential) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(credential)
    }

    private func decode(_ data: Data) throws -> Credential {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Credential.self, from: data)
    }
}
