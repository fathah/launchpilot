import Foundation

struct DetectionResult: Hashable, Sendable {
    let framework: Framework
    let confidence: Confidence
    let evidence: [String]

    enum Confidence: Int, Sendable, Comparable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static let unknown = DetectionResult(framework: .unknown, confidence: .none, evidence: [])
}
