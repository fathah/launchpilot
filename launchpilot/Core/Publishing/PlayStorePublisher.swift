import Foundation

enum PlayStorePublishError: Error, LocalizedError {
    case invalidServiceAccount(String)
    case invalidAAB(URL)
    case http(status: Int, body: String)
    case unexpectedResponse(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidServiceAccount(let detail):
            return "Service account JSON is not valid: \(detail)"
        case .invalidAAB(let url):
            return "AAB not found at \(url.path)"
        case .http(let status, let body):
            return "Google Play API error \(status): \(body.prefix(400))"
        case .unexpectedResponse(let detail):
            return "Unexpected Google Play API response: \(detail)"
        case .cancelled:
            return "Upload cancelled"
        }
    }
}

struct PlayStorePublishRequest: Sendable {
    let packageName: String
    let track: String
    let aabPath: URL
    let releaseName: String?
    let releaseStatus: String  // "draft", "completed", "halted", "inProgress"

    init(
        packageName: String,
        track: String = "internal",
        aabPath: URL,
        releaseName: String? = nil,
        releaseStatus: String = "draft"
    ) {
        self.packageName = packageName
        self.track = track
        self.aabPath = aabPath
        self.releaseName = releaseName
        self.releaseStatus = releaseStatus
    }
}

struct PlayStorePublishResult: Sendable {
    let versionCode: Int
    let editId: String
    let track: String
}

/// Uploads an AAB to Google Play using the Android Publisher v3 Edits API.
///
/// Flow:
///   1. JWT-bearer OAuth2 → access token
///   2. POST edits → editId
///   3. POST upload bundles (media) → versionCode
///   4. PATCH track → attach versionCode
///   5. POST commit → publishes the edit
nonisolated enum PlayStorePublisher {

    private struct ServiceAccount {
        let clientEmail: String
        let privateKey: String
        let tokenURI: String
    }

    static func publish(
        request: PlayStorePublishRequest,
        serviceAccountJSON: String,
        urlSession: URLSession = .shared,
        log: @Sendable (String, LogStream) async -> Void = { _, _ in },
        isCancelled: @Sendable () async -> Bool = { false }
    ) async throws -> PlayStorePublishResult {
        let account = try parseServiceAccount(serviceAccountJSON)
        guard FileManager.default.fileExists(atPath: request.aabPath.path) else {
            throw PlayStorePublishError.invalidAAB(request.aabPath)
        }

        if await isCancelled() { throw PlayStorePublishError.cancelled }

        await log("Authenticating as \(account.clientEmail)…", .stdout)
        let token = try await fetchAccessToken(account: account, urlSession: urlSession)

        if await isCancelled() { throw PlayStorePublishError.cancelled }

        await log("Creating edit for \(request.packageName)…", .stdout)
        let editId = try await createEdit(
            packageName: request.packageName,
            token: token,
            urlSession: urlSession
        )
        await log("editId: \(editId)", .stdout)

        if await isCancelled() { throw PlayStorePublishError.cancelled }

        let aabSize = (try? FileManager.default.attributesOfItem(atPath: request.aabPath.path)[.size] as? Int64) ?? 0
        await log("Uploading \(request.aabPath.lastPathComponent) (\(formatBytes(aabSize)))…", .stdout)
        let versionCode = try await uploadBundle(
            packageName: request.packageName,
            editId: editId,
            aabPath: request.aabPath,
            token: token,
            urlSession: urlSession
        )
        await log("versionCode: \(versionCode)", .stdout)

        if await isCancelled() { throw PlayStorePublishError.cancelled }

        await log("Updating track \(request.track)…", .stdout)
        try await updateTrack(
            packageName: request.packageName,
            editId: editId,
            track: request.track,
            versionCode: versionCode,
            releaseName: request.releaseName,
            releaseStatus: request.releaseStatus,
            token: token,
            urlSession: urlSession
        )

        if await isCancelled() { throw PlayStorePublishError.cancelled }

        await log("Committing edit…", .stdout)
        try await commitEdit(
            packageName: request.packageName,
            editId: editId,
            token: token,
            urlSession: urlSession
        )
        await log("Done. Version \(versionCode) is now on the \(request.track) track.", .stdout)

        return PlayStorePublishResult(versionCode: versionCode, editId: editId, track: request.track)
    }

    // MARK: - Service account

    private static func parseServiceAccount(_ json: String) throws -> ServiceAccount {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlayStorePublishError.invalidServiceAccount("not valid JSON")
        }
        guard let email = root["client_email"] as? String,
              let key = root["private_key"] as? String else {
            throw PlayStorePublishError.invalidServiceAccount("missing client_email or private_key")
        }
        let tokenURI = root["token_uri"] as? String ?? "https://oauth2.googleapis.com/token"
        return ServiceAccount(clientEmail: email, privateKey: key, tokenURI: tokenURI)
    }

    // MARK: - OAuth

    private static func fetchAccessToken(
        account: ServiceAccount,
        urlSession: URLSession
    ) async throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": account.clientEmail,
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": account.tokenURI,
            "iat": now,
            "exp": now + 3600
        ]
        let jwt = try JWTSigner.signRS256(
            header: header,
            claims: claims,
            privateKeyPEM: account.privateKey
        )

        guard let url = URL(string: account.tokenURI) else {
            throw PlayStorePublishError.unexpectedResponse("invalid token URI")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: req)
        try checkStatus(response, data: data)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = dict["access_token"] as? String else {
            throw PlayStorePublishError.unexpectedResponse("no access_token in response")
        }
        return token
    }

    // MARK: - Edits API

    private static let baseURL = "https://androidpublisher.googleapis.com/androidpublisher/v3"
    private static let uploadURL = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"

    private static func createEdit(
        packageName: String,
        token: String,
        urlSession: URLSession
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/applications/\(packageName)/edits") else {
            throw PlayStorePublishError.unexpectedResponse("invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("0", forHTTPHeaderField: "Content-Length")

        let (data, response) = try await urlSession.data(for: req)
        try checkStatus(response, data: data)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String else {
            throw PlayStorePublishError.unexpectedResponse("no edit id")
        }
        return id
    }

    private static func uploadBundle(
        packageName: String,
        editId: String,
        aabPath: URL,
        token: String,
        urlSession: URLSession
    ) async throws -> Int {
        let urlString = "\(uploadURL)/applications/\(packageName)/edits/\(editId)/bundles?uploadType=media"
        guard let url = URL(string: urlString) else {
            throw PlayStorePublishError.unexpectedResponse("invalid upload URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600

        let (data, response) = try await urlSession.upload(for: req, fromFile: aabPath)
        try checkStatus(response, data: data)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlayStorePublishError.unexpectedResponse("upload returned non-JSON body")
        }
        if let code = dict["versionCode"] as? Int { return code }
        if let codeNumber = dict["versionCode"] as? NSNumber { return codeNumber.intValue }
        throw PlayStorePublishError.unexpectedResponse("no versionCode in upload response")
    }

    private static func updateTrack(
        packageName: String,
        editId: String,
        track: String,
        versionCode: Int,
        releaseName: String?,
        releaseStatus: String,
        token: String,
        urlSession: URLSession
    ) async throws {
        let urlString = "\(baseURL)/applications/\(packageName)/edits/\(editId)/tracks/\(track)"
        guard let url = URL(string: urlString) else {
            throw PlayStorePublishError.unexpectedResponse("invalid track URL")
        }
        var release: [String: Any] = [
            "status": releaseStatus,
            "versionCodes": [String(versionCode)]
        ]
        if let releaseName, !releaseName.isEmpty {
            release["name"] = releaseName
        }
        let body: [String: Any] = [
            "track": track,
            "releases": [release]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: req)
        try checkStatus(response, data: data)
    }

    private static func commitEdit(
        packageName: String,
        editId: String,
        token: String,
        urlSession: URLSession
    ) async throws {
        let urlString = "\(baseURL)/applications/\(packageName)/edits/\(editId):commit"
        guard let url = URL(string: urlString) else {
            throw PlayStorePublishError.unexpectedResponse("invalid commit URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("0", forHTTPHeaderField: "Content-Length")

        let (data, response) = try await urlSession.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: - Helpers

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PlayStorePublishError.unexpectedResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw PlayStorePublishError.http(status: http.statusCode, body: body)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
