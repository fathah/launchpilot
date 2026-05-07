import Foundation

enum YAMLCodecError: Error, LocalizedError {
    case encodeFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed(let msg): return "YAML encode failed: \(msg)"
        case .decodeFailed(let msg): return "YAML decode failed: \(msg)"
        }
    }
}

enum YAMLCodec {
    private static let keyOrder: [String: Int] = {
        let keys = [
            "version", "project", "name", "framework", "root", "package_manager", "display_name",
            "apps", "ios", "android",
            "enabled", "bundle_id", "package_name", "scheme", "workspace",
            "configuration", "module", "build_type", "flavor", "artifact_type",
            "export_method", "destination", "track", "team_id",
            "signing", "mode", "provisioning_profile_name", "keystore_ref",
            "build", "output_dir", "archive_path", "ipa_output_dir",
            "environments",
            "commands", "prebuild", "postbuild",
            "publishing", "apple", "google_play",
            "api_key_ref", "app_id", "service_account_ref", "default_track",
            "artifacts", "keep_last", "open_after_build",
            "advanced", "parallel_builds", "verbose_logs"
        ]
        var map: [String: Int] = [:]
        for (i, k) in keys.enumerated() { map[k] = i }
        return map
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let yaml = jsonToYAML(json)
        return YAMLEmitter.emit(yaml)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let yaml = try YAMLParser.parse(text)
        let foundation = yaml.toFoundation()
        let data = try JSONSerialization.data(withJSONObject: foundation, options: [.fragmentsAllowed])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private static func jsonToYAML(_ value: Any) -> YAMLValue {
        if value is NSNull { return .null }
        if let dict = value as? [String: Any] {
            let sorted = dict.keys.sorted { lhs, rhs in
                let li = keyOrder[lhs] ?? Int.max
                let ri = keyOrder[rhs] ?? Int.max
                if li != ri { return li < ri }
                return lhs < rhs
            }
            return .mapping(sorted.map { ($0, jsonToYAML(dict[$0] as Any)) })
        }
        if let arr = value as? [Any] {
            return .sequence(arr.map { jsonToYAML($0) })
        }
        if let num = value as? NSNumber {
            // Distinguish bool vs numeric. NSNumber for bool reports objCType "c".
            let type = String(cString: num.objCType)
            if type == "c" || type == "B" { return .bool(num.boolValue) }
            if num.stringValue.contains(".") || num.stringValue.lowercased().contains("e") {
                return .double(num.doubleValue)
            }
            return .int(num.int64Value)
        }
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool { return .bool(b) }
        return .string("\(value)")
    }
}
