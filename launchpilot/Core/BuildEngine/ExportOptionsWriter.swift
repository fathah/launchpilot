import Foundation

struct IOSExportOptions: Sendable, Hashable {
    var method: String
    var teamID: String?
    var signingStyle: String
    var provisioningProfiles: [String: String]?
    var uploadSymbols: Bool
    var stripSwiftSymbols: Bool
    var compileBitcode: Bool

    init(
        method: String = "app-store",
        teamID: String? = nil,
        signingStyle: String = "automatic",
        provisioningProfiles: [String: String]? = nil,
        uploadSymbols: Bool = true,
        stripSwiftSymbols: Bool = true,
        compileBitcode: Bool = false
    ) {
        self.method = method
        self.teamID = teamID
        self.signingStyle = signingStyle
        self.provisioningProfiles = provisioningProfiles
        self.uploadSymbols = uploadSymbols
        self.stripSwiftSymbols = stripSwiftSymbols
        self.compileBitcode = compileBitcode
    }
}

nonisolated enum ExportOptionsWriter {
    static func plistData(for options: IOSExportOptions) throws -> Data {
        var dict: [String: Any] = [
            "method": options.method,
            "signingStyle": options.signingStyle,
            "uploadSymbols": options.uploadSymbols,
            "stripSwiftSymbols": options.stripSwiftSymbols,
            "compileBitcode": options.compileBitcode
        ]
        if let teamID = options.teamID, !teamID.isEmpty {
            dict["teamID"] = teamID
        }
        if let profiles = options.provisioningProfiles, !profiles.isEmpty {
            dict["provisioningProfiles"] = profiles
        }
        return try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
    }

    @discardableResult
    static func write(at url: URL, options: IOSExportOptions) throws -> URL {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try plistData(for: options)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func from(config: ProjectConfig) -> IOSExportOptions {
        let ios = config.apps.ios
        let mode = ios?.signing?.mode.lowercased()
        let signingStyle = (mode == "manual") ? "manual" : "automatic"

        var profiles: [String: String]? = nil
        if signingStyle == "manual",
           let bundleId = ios?.bundleId, !bundleId.isEmpty,
           let profile = ios?.signing?.provisioningProfileName, !profile.isEmpty {
            profiles = [bundleId: profile]
        }

        return IOSExportOptions(
            method: ios?.exportMethod ?? "app-store",
            teamID: ios?.teamId,
            signingStyle: signingStyle,
            provisioningProfiles: profiles
        )
    }
}
