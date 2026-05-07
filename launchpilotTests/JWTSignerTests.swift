import Testing
import Foundation
import Security
@testable import launchpilot

struct JWTSignerTests {

    private func generateRSAKeyPEM() -> String {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let derCF = SecKeyCopyExternalRepresentation(key, &error) else {
            return ""
        }
        let der = derCF as Data
        // SecKeyCopyExternalRepresentation returns PKCS#1 for RSA private keys.
        let base64 = der.base64EncodedString()
        return "-----BEGIN RSA PRIVATE KEY-----\n\(base64)\n-----END RSA PRIVATE KEY-----"
    }

    private func wrapPKCS1AsPKCS8(_ pkcs1PEM: String) -> String? {
        // Strip the PKCS#1 PEM into raw DER.
        let body = pkcs1PEM
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let pkcs1 = Data(base64Encoded: body) else { return nil }

        // PKCS#8 wrapper:
        //   SEQUENCE {
        //     INTEGER 0,
        //     SEQUENCE { OID 1.2.840.113549.1.1.1 (rsaEncryption), NULL },
        //     OCTET STRING <pkcs1>
        //   }
        let rsaOID: [UInt8] = [
            0x30, 0x0D,                                     // SEQUENCE (13 bytes)
            0x06, 0x09,                                     // OID (9 bytes)
            0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
            0x05, 0x00                                      // NULL
        ]
        var inner: [UInt8] = []
        inner.append(0x02); inner.append(0x01); inner.append(0x00)  // INTEGER 0
        inner.append(contentsOf: rsaOID)
        inner.append(0x04)                                          // OCTET STRING
        inner.append(contentsOf: encodeASN1Length(pkcs1.count))
        inner.append(contentsOf: [UInt8](pkcs1))

        var outer: [UInt8] = [0x30]
        outer.append(contentsOf: encodeASN1Length(inner.count))
        outer.append(contentsOf: inner)

        let pkcs8Data = Data(outer)
        let base64 = pkcs8Data.base64EncodedString()
        return "-----BEGIN PRIVATE KEY-----\n\(base64)\n-----END PRIVATE KEY-----"
    }

    private func encodeASN1Length(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var n = length
        while n > 0 { bytes.insert(UInt8(n & 0xFF), at: 0); n >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    @Test func signsRS256JWTWithPKCS1Key() throws {
        let pem = generateRSAKeyPEM()
        #expect(!pem.isEmpty)

        let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": "test@example.iam.gserviceaccount.com",
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": 1700000000,
            "exp": 1700003600
        ]
        let jwt: String
        do {
            jwt = try JWTSigner.signRS256(header: header, claims: claims, privateKeyPEM: pem)
        } catch {
            Issue.record("signRS256 threw: \(error)")
            return
        }
        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3)

        if let data = base64URLDecode(String(parts[0])),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #expect(dict["alg"] as? String == "RS256")
            #expect(dict["typ"] as? String == "JWT")
        } else {
            Issue.record("header did not decode")
        }
        #expect(!parts[2].isEmpty)
    }

    @Test func signsRS256JWTWithPKCS8Key() throws {
        let pkcs1 = generateRSAKeyPEM()
        guard let pkcs8 = wrapPKCS1AsPKCS8(pkcs1) else {
            Issue.record("could not wrap PKCS#1 as PKCS#8")
            return
        }
        let jwt = try JWTSigner.signRS256(
            header: ["alg": "RS256", "typ": "JWT"],
            claims: ["sub": "x"],
            privateKeyPEM: pkcs8
        )
        #expect(jwt.split(separator: ".").count == 3)
    }

    @Test func rejectsInvalidPEM() throws {
        #expect(throws: JWTSigningError.self) {
            _ = try JWTSigner.signRS256(
                header: ["alg": "RS256"],
                claims: ["sub": "x"],
                privateKeyPEM: "not a key"
            )
        }
    }

    private func base64URLDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - t.count % 4) % 4
        t.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: t)
    }
}
