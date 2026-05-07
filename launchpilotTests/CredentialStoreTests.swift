import Testing
import Foundation
@testable import launchpilot

struct CredentialStoreTests {

    private func makeStore() -> (CredentialStore, () -> Void) {
        let service = "com.fathaaah.launchpilot.tests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        let store = CredentialStore(keychain: keychain)
        let cleanup = {
            for ref in (try? keychain.listRefs()) ?? [] {
                try? keychain.delete(ref: ref)
            }
        }
        return (store, cleanup)
    }

    private func sampleApple(ref: String = "apple-main") -> Credential {
        Credential(
            ref: ref,
            displayName: "Apple Production Key",
            secret: .appleAPIKey(AppleAPIKeySecret(
                keyId: "ABC123",
                issuerId: "11111111-2222-3333-4444-555555555555",
                teamId: "TEAM12",
                p8Contents: "-----BEGIN PRIVATE KEY-----\nMIG...test...\n-----END PRIVATE KEY-----"
            ))
        )
    }

    @Test func savesAndReadsCredential() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let credential = sampleApple()
        try store.save(credential, isNew: true)

        let loaded = try store.read(ref: credential.ref)
        #expect(loaded?.ref == credential.ref)
        #expect(loaded?.displayName == credential.displayName)
        if case .appleAPIKey(let secret) = loaded?.secret {
            #expect(secret.keyId == "ABC123")
            #expect(secret.teamId == "TEAM12")
        } else {
            Issue.record("expected Apple API key payload")
        }
    }

    @Test func rejectsDuplicateRef() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(), isNew: true)
        #expect(throws: CredentialStoreError.self) {
            try store.save(sampleApple(), isNew: true)
        }
    }

    @Test func updatingExistingRefDoesNotRequireIsNew() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(), isNew: true)
        var updated = sampleApple()
        updated.displayName = "Updated label"
        try store.save(updated, isNew: false)

        let loaded = try store.read(ref: updated.ref)
        #expect(loaded?.displayName == "Updated label")
    }

    @Test func renameMovesEntry() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(ref: "apple-old"), isNew: true)
        try store.rename(from: "apple-old", to: "apple-new")

        #expect(try store.read(ref: "apple-old") == nil)
        #expect(try store.read(ref: "apple-new")?.ref == "apple-new")
    }

    @Test func renameRejectsCollidingTarget() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(ref: "a"), isNew: true)
        try store.save(sampleApple(ref: "b"), isNew: true)
        #expect(throws: CredentialStoreError.self) {
            try store.rename(from: "a", to: "b")
        }
    }

    @Test func deletesCredential() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(), isNew: true)
        try store.delete(ref: "apple-main")
        #expect(try store.read(ref: "apple-main") == nil)
    }

    @Test func validatesRefFormat() throws {
        #expect(throws: CredentialStoreError.self) {
            try CredentialStore.validate(ref: "invalid ref with spaces")
        }
        #expect(throws: CredentialStoreError.self) {
            try CredentialStore.validate(ref: "")
        }
        try CredentialStore.validate(ref: "valid_ref-1.test")
    }

    @Test func listingReturnsSavedCredentials() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(sampleApple(ref: "alpha"), isNew: true)
        try store.save(sampleApple(ref: "beta"), isNew: true)
        let list = store.list()
        #expect(list.count == 2)
        #expect(Set(list.map(\.ref)) == ["alpha", "beta"])
    }

    @Test func googleAndKeystoreRoundTrip() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let google = Credential(
            ref: "google-internal",
            displayName: "Internal Google Play",
            secret: .googlePlayServiceAccount(GooglePlayServiceAccountSecret(
                jsonContents: #"{"type":"service_account","client_email":"foo@x.iam.gserviceaccount.com"}"#,
                clientEmail: "foo@x.iam.gserviceaccount.com"
            ))
        )
        try store.save(google, isNew: true)
        if case .googlePlayServiceAccount(let secret) = try store.read(ref: "google-internal")?.secret {
            #expect(secret.clientEmail == "foo@x.iam.gserviceaccount.com")
        } else {
            Issue.record("expected Google Play payload")
        }

        let keystore = Credential(
            ref: "android-prod",
            displayName: "Production keystore",
            secret: .androidKeystore(AndroidKeystoreSecret(
                keystorePath: "/Users/example/keystores/release.jks",
                keystorePassword: "k-pass",
                keyAlias: "release",
                keyPassword: "key-pass"
            ))
        )
        try store.save(keystore, isNew: true)
        if case .androidKeystore(let secret) = try store.read(ref: "android-prod")?.secret {
            #expect(secret.keystorePath == "/Users/example/keystores/release.jks")
            #expect(secret.keystorePassword == "k-pass")
            #expect(secret.keyAlias == "release")
        } else {
            Issue.record("expected Android keystore payload")
        }
    }
}
