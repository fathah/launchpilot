import Foundation

enum YAMLParseError: Error, LocalizedError {
    case unexpectedToken(line: Int, message: String)
    case invalidIndent(line: Int)
    case invalidScalar(line: Int, value: String)

    var errorDescription: String? {
        switch self {
        case .unexpectedToken(let line, let message):
            return "YAML parse error on line \(line): \(message)"
        case .invalidIndent(let line):
            return "YAML invalid indentation on line \(line)"
        case .invalidScalar(let line, let value):
            return "YAML invalid scalar on line \(line): \(value)"
        }
    }
}

struct YAMLParser {
    private struct Line {
        let number: Int
        let indent: Int
        let content: String
    }

    private let lines: [Line]
    private var index: Int = 0

    init(text: String) {
        var collected: [Line] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let lineNumber = i + 1
            let stripped = Self.stripComment(raw)
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indent = stripped.prefix(while: { $0 == " " }).count
            let content = String(stripped.dropFirst(indent))
            collected.append(Line(number: lineNumber, indent: indent, content: content))
        }
        self.lines = collected
    }

    static func parse(_ text: String) throws -> YAMLValue {
        var parser = YAMLParser(text: text)
        guard !parser.lines.isEmpty else { return .mapping([]) }
        let baseIndent = parser.lines[0].indent
        return try parser.parseNode(parentIndent: -1, currentIndent: baseIndent)
    }

    private mutating func parseNode(parentIndent: Int, currentIndent: Int) throws -> YAMLValue {
        guard index < lines.count else { return .null }
        let line = lines[index]
        if line.content.hasPrefix("- ") || line.content == "-" {
            return try parseSequence(indent: currentIndent)
        }
        return try parseMapping(indent: currentIndent)
    }

    private mutating func parseMapping(indent: Int) throws -> YAMLValue {
        var pairs: [(String, YAMLValue)] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLParseError.invalidIndent(line: line.number)
            }
            guard let (key, rest) = Self.splitKey(line.content) else {
                throw YAMLParseError.unexpectedToken(line: line.number, message: "expected key")
            }
            index += 1
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    let childIndent = lines[index].indent
                    let childLine = lines[index]
                    if childLine.content.hasPrefix("- ") || childLine.content == "-" {
                        let seq = try parseSequence(indent: childIndent)
                        pairs.append((key, seq))
                    } else {
                        let nested = try parseMapping(indent: childIndent)
                        pairs.append((key, nested))
                    }
                } else {
                    pairs.append((key, .null))
                }
            } else {
                pairs.append((key, try Self.parseInlineScalar(trimmed, line: line.number)))
            }
        }
        return .mapping(pairs)
    }

    private mutating func parseSequence(indent: Int) throws -> YAMLValue {
        var items: [YAMLValue] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent {
                throw YAMLParseError.invalidIndent(line: line.number)
            }
            guard line.content.hasPrefix("- ") || line.content == "-" else { break }
            let after = line.content == "-" ? "" : String(line.content.dropFirst(2))
            let trimmed = after.trimmingCharacters(in: .whitespaces)
            index += 1
            if trimmed.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    let childIndent = lines[index].indent
                    let childLine = lines[index]
                    if childLine.content.hasPrefix("- ") || childLine.content == "-" {
                        items.append(try parseSequence(indent: childIndent))
                    } else {
                        items.append(try parseMapping(indent: childIndent))
                    }
                } else {
                    items.append(.null)
                }
            } else if let (key, rest) = Self.splitKey(after) {
                let restTrim = rest.trimmingCharacters(in: .whitespaces)
                var pairs: [(String, YAMLValue)] = []
                if restTrim.isEmpty {
                    if index < lines.count, lines[index].indent > indent {
                        let childIndent = lines[index].indent
                        let childLine = lines[index]
                        let value: YAMLValue
                        if childLine.content.hasPrefix("- ") || childLine.content == "-" {
                            value = try parseSequence(indent: childIndent)
                        } else {
                            value = try parseMapping(indent: childIndent)
                        }
                        pairs.append((key, value))
                    } else {
                        pairs.append((key, .null))
                    }
                } else {
                    pairs.append((key, try Self.parseInlineScalar(restTrim, line: line.number)))
                }
                let inlineIndent = indent + 2
                while index < lines.count, lines[index].indent == inlineIndent,
                      !lines[index].content.hasPrefix("- "),
                      lines[index].content != "-" {
                    let l = lines[index]
                    guard let (k, r) = Self.splitKey(l.content) else { break }
                    index += 1
                    let rTrim = r.trimmingCharacters(in: .whitespaces)
                    if rTrim.isEmpty {
                        if index < lines.count, lines[index].indent > inlineIndent {
                            let childIndent = lines[index].indent
                            let childLine = lines[index]
                            let v: YAMLValue
                            if childLine.content.hasPrefix("- ") || childLine.content == "-" {
                                v = try parseSequence(indent: childIndent)
                            } else {
                                v = try parseMapping(indent: childIndent)
                            }
                            pairs.append((k, v))
                        } else {
                            pairs.append((k, .null))
                        }
                    } else {
                        pairs.append((k, try Self.parseInlineScalar(rTrim, line: l.number)))
                    }
                }
                items.append(.mapping(pairs))
            } else {
                items.append(try Self.parseInlineScalar(trimmed, line: line.number))
            }
        }
        return .sequence(items)
    }

    private static func splitKey(_ content: String) -> (String, String)? {
        if let first = content.first, first == "\"" || first == "'" {
            let quote = first
            var escaped = false
            var end: String.Index?
            var i = content.index(after: content.startIndex)
            while i < content.endIndex {
                let ch = content[i]
                if escaped { escaped = false; content.formIndex(after: &i); continue }
                if ch == "\\" && quote == "\"" { escaped = true; content.formIndex(after: &i); continue }
                if ch == quote { end = i; break }
                content.formIndex(after: &i)
            }
            guard let endIdx = end else { return nil }
            let key = String(content[content.index(after: content.startIndex)..<endIdx])
            let after = content.index(after: endIdx)
            guard after < content.endIndex, content[after] == ":" else { return nil }
            let rest = String(content[content.index(after: after)...])
            return (key, rest)
        }
        var inSingle = false, inDouble = false
        for i in content.indices {
            let ch = content[i]
            if ch == "'" && !inDouble { inSingle.toggle() }
            else if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == ":" && !inSingle && !inDouble {
                let key = String(content[content.startIndex..<i]).trimmingCharacters(in: .whitespaces)
                let rest = String(content[content.index(after: i)...])
                return (key, rest)
            }
        }
        return nil
    }

    private static func parseInlineScalar(_ raw: String, line: Int) throws -> YAMLValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "~" || s.lowercased() == "null" { return .null }
        if s == "true" || s == "True" || s == "TRUE" { return .bool(true) }
        if s == "false" || s == "False" || s == "FALSE" { return .bool(false) }
        if s == "[]" { return .sequence([]) }
        if s == "{}" { return .mapping([]) }
        if let first = s.first {
            if first == "\"" || first == "'" {
                return .string(try unquote(s, line: line))
            }
            if first == "[" {
                return try parseFlowSequence(s, line: line)
            }
            if first == "{" {
                return try parseFlowMapping(s, line: line)
            }
        }
        if let int = Int64(s) { return .int(int) }
        if let double = Double(s), s.contains(".") || s.lowercased().contains("e") {
            return .double(double)
        }
        return .string(s)
    }

    private static func unquote(_ s: String, line: Int) throws -> String {
        guard s.count >= 2, let first = s.first, let last = s.last, first == last,
              first == "\"" || first == "'" else {
            throw YAMLParseError.invalidScalar(line: line, value: s)
        }
        let inner = String(s.dropFirst().dropLast())
        if first == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        var result = ""
        var i = inner.startIndex
        while i < inner.endIndex {
            let ch = inner[i]
            if ch == "\\" {
                let next = inner.index(after: i)
                guard next < inner.endIndex else { break }
                let escape = inner[next]
                switch escape {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "0": result.append("\0")
                default: result.append(escape)
                }
                i = inner.index(after: next)
            } else {
                result.append(ch)
                i = inner.index(after: i)
            }
        }
        return result
    }

    private static func parseFlowSequence(_ s: String, line: Int) throws -> YAMLValue {
        guard s.hasPrefix("["), s.hasSuffix("]") else {
            throw YAMLParseError.invalidScalar(line: line, value: s)
        }
        let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return .sequence([]) }
        let parts = splitFlow(inner)
        let values = try parts.map { try parseInlineScalar($0, line: line) }
        return .sequence(values)
    }

    private static func parseFlowMapping(_ s: String, line: Int) throws -> YAMLValue {
        guard s.hasPrefix("{"), s.hasSuffix("}") else {
            throw YAMLParseError.invalidScalar(line: line, value: s)
        }
        let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return .mapping([]) }
        let parts = splitFlow(inner)
        var pairs: [(String, YAMLValue)] = []
        for part in parts {
            guard let (k, v) = splitKey(part) else {
                throw YAMLParseError.invalidScalar(line: line, value: part)
            }
            pairs.append((k, try parseInlineScalar(v.trimmingCharacters(in: .whitespaces), line: line)))
        }
        return .mapping(pairs)
    }

    private static func splitFlow(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inSingle = false, inDouble = false
        for ch in s {
            if ch == "'" && !inDouble { inSingle.toggle() }
            else if ch == "\"" && !inSingle { inDouble.toggle() }
            else if !inSingle && !inDouble {
                if ch == "[" || ch == "{" { depth += 1 }
                else if ch == "]" || ch == "}" { depth -= 1 }
                else if ch == "," && depth == 0 {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    continue
                }
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts
    }

    private static func stripComment(_ line: String) -> String {
        var inSingle = false, inDouble = false
        for i in line.indices {
            let ch = line[i]
            if ch == "'" && !inDouble { inSingle.toggle() }
            else if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == "#" && !inSingle && !inDouble {
                if i == line.startIndex {
                    return ""
                }
                let prev = line.index(before: i)
                if line[prev] == " " || line[prev] == "\t" {
                    return String(line[line.startIndex..<i])
                }
            }
        }
        return line
    }
}
