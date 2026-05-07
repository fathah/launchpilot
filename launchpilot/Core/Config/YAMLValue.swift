import Foundation

indirect enum YAMLValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case sequence([YAMLValue])
    case mapping([(String, YAMLValue)])

    static func == (lhs: YAMLValue, rhs: YAMLValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.sequence(let a), .sequence(let b)): return a == b
        case (.mapping(let a), .mapping(let b)):
            guard a.count == b.count else { return false }
            for (lhs, rhs) in zip(a, b) where lhs.0 != rhs.0 || lhs.1 != rhs.1 {
                return false
            }
            return true
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .bool(let v): hasher.combine(1); hasher.combine(v)
        case .int(let v): hasher.combine(2); hasher.combine(v)
        case .double(let v): hasher.combine(3); hasher.combine(v)
        case .string(let v): hasher.combine(4); hasher.combine(v)
        case .sequence(let v): hasher.combine(5); hasher.combine(v)
        case .mapping(let v):
            hasher.combine(6)
            for (k, val) in v {
                hasher.combine(k)
                hasher.combine(val)
            }
        }
    }
}

extension YAMLValue {
    func toFoundation() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .sequence(let arr): return arr.map { $0.toFoundation() }
        case .mapping(let pairs):
            var dict: [String: Any] = [:]
            for (k, v) in pairs { dict[k] = v.toFoundation() }
            return dict
        }
    }
}
