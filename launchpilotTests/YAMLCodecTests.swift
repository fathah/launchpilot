import Testing
import Foundation
@testable import launchpilot

struct YAMLCodecTests {

    @Test func roundTripDefaultFlutter() throws {
        let original = ProjectConfig.defaults(name: "Prism Mobile", framework: .flutter)
        let yaml = try YAMLCodec.encode(original)
        let decoded = try YAMLCodec.decode(ProjectConfig.self, from: yaml)
        #expect(decoded == original)
    }

    @Test func roundTripDefaultNativeIOS() throws {
        let original = ProjectConfig.defaults(name: "MyApp", framework: .nativeIOS)
        let yaml = try YAMLCodec.encode(original)
        let decoded = try YAMLCodec.decode(ProjectConfig.self, from: yaml)
        #expect(decoded == original)
    }

    @Test func roundTripDefaultNativeAndroid() throws {
        let original = ProjectConfig.defaults(name: "MyApp", framework: .nativeAndroid)
        let yaml = try YAMLCodec.encode(original)
        let decoded = try YAMLCodec.decode(ProjectConfig.self, from: yaml)
        #expect(decoded == original)
    }

    @Test func emitsExpectedTopLevelOrder() throws {
        let cfg = ProjectConfig.defaults(name: "Demo", framework: .flutter)
        let yaml = try YAMLCodec.encode(cfg)
        let lines = yaml.split(separator: "\n").map(String.init)
        let topLevel = lines.filter { !$0.hasPrefix(" ") && $0.contains(":") }
                            .map { $0.prefix(while: { $0 != ":" }) }
                            .map(String.init)
        #expect(topLevel.first == "version")
        #expect(topLevel.contains("project"))
        #expect(topLevel.contains("apps"))
        #expect(topLevel.contains("environments"))
        #expect(topLevel.contains("publishing"))
    }

    @Test func parsesEmptyContainers() throws {
        let yaml = """
        version: 1
        commands:
          prebuild: []
          postbuild: []
        """
        let value = try YAMLParser.parse(yaml)
        guard case .mapping(let pairs) = value else {
            Issue.record("expected mapping")
            return
        }
        #expect(pairs.contains(where: { $0.0 == "version" }))
        #expect(pairs.contains(where: { $0.0 == "commands" }))
    }

    @Test func handlesQuotedStrings() throws {
        let yaml = """
        a: "hello world"
        b: 'single quoted'
        c: "with: colon"
        """
        let value = try YAMLParser.parse(yaml)
        guard case .mapping(let pairs) = value else {
            Issue.record("expected mapping")
            return
        }
        #expect(pairs[0].1 == .string("hello world"))
        #expect(pairs[1].1 == .string("single quoted"))
        #expect(pairs[2].1 == .string("with: colon"))
    }
}
