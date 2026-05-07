import Foundation

enum YAMLEmitter {
    static func emit(_ value: YAMLValue) -> String {
        var out = ""
        switch value {
        case .mapping(let pairs):
            emitMapping(pairs, indent: 0, into: &out)
        case .sequence(let items):
            emitSequence(items, indent: 0, into: &out)
        default:
            out += scalarString(for: value) + "\n"
        }
        return out
    }

    private static func emitMapping(_ pairs: [(String, YAMLValue)], indent: Int, into out: inout String) {
        if pairs.isEmpty {
            // empty inline mapping shouldn't happen at top — caller handles
            return
        }
        let pad = String(repeating: " ", count: indent)
        for (key, value) in pairs {
            switch value {
            case .mapping(let children):
                if children.isEmpty {
                    out += "\(pad)\(key): {}\n"
                } else {
                    out += "\(pad)\(key):\n"
                    emitMapping(children, indent: indent + 2, into: &out)
                }
            case .sequence(let items):
                if items.isEmpty {
                    out += "\(pad)\(key): []\n"
                } else {
                    out += "\(pad)\(key):\n"
                    emitSequence(items, indent: indent + 2, into: &out)
                }
            default:
                out += "\(pad)\(key): \(scalarString(for: value))\n"
            }
        }
    }

    private static func emitSequence(_ items: [YAMLValue], indent: Int, into out: inout String) {
        let pad = String(repeating: " ", count: indent)
        for item in items {
            switch item {
            case .mapping(let pairs):
                if pairs.isEmpty {
                    out += "\(pad)- {}\n"
                } else {
                    out += "\(pad)- "
                    var first = true
                    for (key, value) in pairs {
                        let linePad = first ? "" : String(repeating: " ", count: indent + 2)
                        first = false
                        switch value {
                        case .mapping(let children):
                            if children.isEmpty {
                                out += "\(linePad)\(key): {}\n"
                            } else {
                                out += "\(linePad)\(key):\n"
                                emitMapping(children, indent: indent + 4, into: &out)
                            }
                        case .sequence(let nested):
                            if nested.isEmpty {
                                out += "\(linePad)\(key): []\n"
                            } else {
                                out += "\(linePad)\(key):\n"
                                emitSequence(nested, indent: indent + 4, into: &out)
                            }
                        default:
                            out += "\(linePad)\(key): \(scalarString(for: value))\n"
                        }
                    }
                }
            case .sequence(let nested):
                if nested.isEmpty {
                    out += "\(pad)- []\n"
                } else {
                    out += "\(pad)-\n"
                    emitSequence(nested, indent: indent + 2, into: &out)
                }
            default:
                out += "\(pad)- \(scalarString(for: item))\n"
            }
        }
    }

    private static func scalarString(for value: YAMLValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v):
            if v.isNaN { return ".nan" }
            if v.isInfinite { return v > 0 ? ".inf" : "-.inf" }
            if v == v.rounded() && abs(v) < 1e16 {
                return "\(Int64(v)).0"
            }
            return String(v)
        case .string(let s): return quoteIfNeeded(s)
        case .sequence: return "[]"
        case .mapping: return "{}"
        }
    }

    private static func quoteIfNeeded(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        let reserved: Set<String> = [
            "true", "false", "null", "yes", "no", "on", "off",
            "True", "False", "Null", "TRUE", "FALSE", "NULL",
            "~"
        ]
        if reserved.contains(s) { return "\"\(s)\"" }
        if Int64(s) != nil || Double(s) != nil { return "\"\(s)\"" }

        let specials: Set<Character> = [":", "#", "&", "*", "!", "|", ">", "%", "@", "`", "{", "}", "[", "]", ",", "\"", "'", "\\"]
        var needsQuote = false
        if let first = s.first, "-?: ".contains(first) { needsQuote = true }
        if !needsQuote {
            for ch in s where specials.contains(ch) || ch.isNewline {
                needsQuote = true
                break
            }
        }
        if s.hasSuffix(" ") || s.hasPrefix(" ") { needsQuote = true }
        guard needsQuote else { return s }

        var escaped = ""
        for ch in s {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(ch)
            }
        }
        return "\"\(escaped)\""
    }
}
