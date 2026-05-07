import Foundation

enum Framework: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case flutter
    case expo
    case reactNative = "react_native"
    case nativeIOS = "native_ios"
    case nativeAndroid = "native_android"
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flutter: return "Flutter"
        case .expo: return "Expo"
        case .reactNative: return "React Native"
        case .nativeIOS: return "Native iOS"
        case .nativeAndroid: return "Native Android"
        case .unknown: return "Unknown"
        }
    }

    var supportsIOS: Bool {
        switch self {
        case .flutter, .expo, .reactNative, .nativeIOS: return true
        case .nativeAndroid, .unknown: return false
        }
    }

    var supportsAndroid: Bool {
        switch self {
        case .flutter, .expo, .reactNative, .nativeAndroid: return true
        case .nativeIOS, .unknown: return false
        }
    }
}
