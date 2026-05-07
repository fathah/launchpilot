import Testing
import Foundation
@testable import launchpilot

struct ExportOptionsWriterTests {

    private func parsedPlist(_ data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return (object as? [String: Any]) ?? [:]
    }

    @Test func defaultsProduceAppStoreAutomatic() throws {
        let options = IOSExportOptions()
        let data = try ExportOptionsWriter.plistData(for: options)
        let dict = try parsedPlist(data)

        #expect(dict["method"] as? String == "app-store")
        #expect(dict["signingStyle"] as? String == "automatic")
        #expect(dict["uploadSymbols"] as? Bool == true)
        #expect(dict["stripSwiftSymbols"] as? Bool == true)
        #expect(dict["compileBitcode"] as? Bool == false)
        #expect(dict["teamID"] == nil)
        #expect(dict["provisioningProfiles"] == nil)
    }

    @Test func includesTeamIDWhenProvided() throws {
        let options = IOSExportOptions(teamID: "ABCDE12345")
        let data = try ExportOptionsWriter.plistData(for: options)
        let dict = try parsedPlist(data)
        #expect(dict["teamID"] as? String == "ABCDE12345")
    }

    @Test func manualSigningEmitsProvisioningProfiles() throws {
        let options = IOSExportOptions(
            method: "ad-hoc",
            teamID: "TEAM",
            signingStyle: "manual",
            provisioningProfiles: ["org.example.app": "My Profile"]
        )
        let data = try ExportOptionsWriter.plistData(for: options)
        let dict = try parsedPlist(data)
        #expect(dict["signingStyle"] as? String == "manual")
        #expect(dict["method"] as? String == "ad-hoc")
        let profiles = dict["provisioningProfiles"] as? [String: String]
        #expect(profiles?["org.example.app"] == "My Profile")
    }

    @Test func writesToDiskAndCreatesIntermediateDirs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("nested/launchpilot/ExportOptions.plist")
        let written = try ExportOptionsWriter.write(at: target, options: IOSExportOptions(teamID: "T1"))
        #expect(FileManager.default.fileExists(atPath: written.path))

        let data = try Data(contentsOf: written)
        let dict = try parsedPlist(data)
        #expect(dict["teamID"] as? String == "T1")
    }

    @Test func fromConfigPicksUpManualSigningWhenSet() throws {
        var config = ProjectConfig.defaults(name: "Demo", framework: .nativeIOS)
        config.apps.ios?.bundleId = "org.example.app"
        config.apps.ios?.teamId = "TEAM12"
        config.apps.ios?.exportMethod = "ad-hoc"
        config.apps.ios?.signing = ProjectConfig.IOSSigning(
            mode: "manual",
            provisioningProfileName: "Internal Profile"
        )
        let options = ExportOptionsWriter.from(config: config)
        #expect(options.method == "ad-hoc")
        #expect(options.signingStyle == "manual")
        #expect(options.teamID == "TEAM12")
        #expect(options.provisioningProfiles?["org.example.app"] == "Internal Profile")
    }

    @Test func fromConfigDefaultsToAutomaticSigning() throws {
        let config = ProjectConfig.defaults(name: "Demo", framework: .flutter)
        let options = ExportOptionsWriter.from(config: config)
        #expect(options.signingStyle == "automatic")
        #expect(options.method == "app-store")
    }
}
