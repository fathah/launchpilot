import Foundation
import Security

enum JWTSigningError: Error, LocalizedError {
    case invalidPEM
    case unsupportedKeyFormat(String)
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPEM: return "Invalid PEM private key"
        case .unsupportedKeyFormat(let detail): return "Unsupported key format: \(detail)"
        case .signingFailed(let detail): return "JWT signing failed: \(detail)"
        }
    }
}

/// RS256 JSON Web Token signer for Google service accounts.
///
/// The private_key in a Google service-account JSON is PKCS#8 PEM. SecKey on
/// macOS only accepts PKCS#1 DER for RSA keys, so we strip the PKCS#8 wrapper
/// before constructing the SecKey.
nonisolated enum JWTSigner {

    static func signRS256(
        header: [String: Any],
        claims: [String: Any],
        privateKeyPEM: String
    ) throws -> String {
        let headerJSON = try canonicalJSON(header)
        let claimsJSON = try canonicalJSON(claims)
        let signingInput = headerJSON.base64URLEncoded() + "." + claimsJSON.base64URLEncoded()
        guard let signingData = signingInput.data(using: .utf8) else {
            throw JWTSigningError.signingFailed("could not encode signing input")
        }

        let key = try makePrivateKey(from: privateKeyPEM)
        var error: Unmanaged<CFError>?
        guard let signatureCF = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingData as CFData,
            &error
        ) else {
            let detail = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw JWTSigningError.signingFailed(detail)
        }
        let signature = signatureCF as Data
        return signingInput + "." + signature.base64URLEncoded()
    }

    // MARK: - Key parsing

    private static func makePrivateKey(from pem: String) throws -> SecKey {
        let der = try decodePEM(pem)
        let pkcs1: Data
        if isPKCS8(der) {
            pkcs1 = try stripPKCS8Wrapper(der)
        } else {
            pkcs1 = der
        }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            let detail = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw JWTSigningError.unsupportedKeyFormat(detail)
        }
        return key
    }

    private static func decodePEM(_ pem: String) throws -> Data {
        let normalized = pem
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalized
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .filter { !$0.hasPrefix("-----") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let body = lines.joined()
        guard !body.isEmpty,
              let data = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]) else {
            throw JWTSigningError.invalidPEM
        }
        return data
    }

    /// PKCS#8 starts with SEQUENCE { INTEGER version, SEQUENCE algorithm }, which
    /// reliably begins `30 LL 02 01 00 30 ...`. PKCS#1 starts with SEQUENCE { INTEGER 0, ... }
    /// where the second INTEGER is the modulus — never an algorithm SEQUENCE.
    private static func isPKCS8(_ der: Data) -> Bool {
        let bytes = [UInt8](der)
        guard bytes.count > 6, bytes[0] == 0x30 else { return false }
        var idx = 1
        _ = readASN1Length(bytes, &idx)
        guard idx + 5 <= bytes.count else { return false }
        return bytes[idx] == 0x02 && bytes[idx + 1] == 0x01 && bytes[idx + 2] == 0x00
            && bytes[idx + 3] == 0x30
    }

    private static func stripPKCS8Wrapper(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        var i = 0
        guard bytes[i] == 0x30 else { throw JWTSigningError.unsupportedKeyFormat("expected outer SEQUENCE") }
        i += 1
        _ = readASN1Length(bytes, &i)

        // INTEGER version
        guard bytes[i] == 0x02 else { throw JWTSigningError.unsupportedKeyFormat("expected version INTEGER") }
        i += 1
        let vLen = readASN1Length(bytes, &i)
        i += vLen

        // SEQUENCE algorithm
        guard bytes[i] == 0x30 else { throw JWTSigningError.unsupportedKeyFormat("expected algorithm SEQUENCE") }
        i += 1
        let aLen = readASN1Length(bytes, &i)
        i += aLen

        // OCTET STRING (PKCS#1 RSAPrivateKey)
        guard bytes[i] == 0x04 else { throw JWTSigningError.unsupportedKeyFormat("expected OCTET STRING") }
        i += 1
        let oLen = readASN1Length(bytes, &i)
        guard i + oLen <= bytes.count else {
            throw JWTSigningError.unsupportedKeyFormat("OCTET STRING runs past key data")
        }
        return Data(bytes[i..<(i + oLen)])
    }

    private static func readASN1Length(_ bytes: [UInt8], _ i: inout Int) -> Int {
        let first = bytes[i]
        i += 1
        if first < 0x80 { return Int(first) }
        let count = Int(first - 0x80)
        var length = 0
        for _ in 0..<count {
            length = length * 256 + Int(bytes[i])
            i += 1
        }
        return length
    }

    private static func canonicalJSON(_ object: [String: Any]) throws -> Data {
        // Standard JWT serialization uses sortedKeys for determinism.
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        var s = base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }
}

private extension String {
    func base64URLEncoded() -> String {
        Data(utf8).base64URLEncoded()
    }
}
