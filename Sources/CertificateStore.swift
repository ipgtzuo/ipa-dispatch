import Foundation

enum CertificateStore {
    enum StoreError: LocalizedError {
        case invalidProfile
        case expiredProfile
        case wrongPassword
        case noIdentity
        case missingFiles
        case copyFailed

        var errorDescription: String? {
            switch self {
            case .invalidProfile: return "Could not read the provisioning profile."
            case .expiredProfile: return "The provisioning profile is expired."
            case .wrongPassword: return "The p12 password is incorrect or the file is damaged."
            case .noIdentity: return "The p12 does not contain a usable code-signing identity."
            case .missingFiles: return "Select both a p12 and a mobileprovision file."
            case .copyFailed: return "Could not copy the certificate files."
            }
        }
    }

    static func load() -> [CertificateRecord] {
        if let data = try? Data(contentsOf: AppPaths.certificateIndex),
           let records = try? JSONDecoder().decode([CertificateRecord].self, from: data) {
            if !records.isEmpty { return records }
        }
        if let seeded = seedBuiltIn() {
            return [seeded]
        }
        return []
    }

    static func save(_ records: [CertificateRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: AppPaths.certificateIndex, options: .atomic)
        }
    }

    static func seedBuiltIn() -> CertificateRecord? {
        guard FileManager.default.fileExists(atPath: AppPaths.bundledP12.path),
              FileManager.default.fileExists(atPath: AppPaths.bundledProfile.path),
              let profile = try? parseProfile(AppPaths.bundledProfile) else { return nil }
        let id = UUID()
        let dir = AppPaths.certificateDirectory(id)
        do {
            try FileManager.default.copyItem(at: AppPaths.bundledP12, to: dir.appendingPathComponent("cert.p12"))
            try FileManager.default.copyItem(at: AppPaths.bundledProfile, to: dir.appendingPathComponent("profile.mobileprovision"))
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("cert.p12").path)
            let record = CertificateRecord(
                id: id,
                displayName: "Built-in certificate",
                profileName: profile.name,
                teamID: profile.teamID,
                appID: profile.appID,
                expires: profile.expires,
                provisionedDevices: profile.devices,
                allDevices: profile.allDevices,
                isBuiltIn: true,
                importedAt: Date()
            )
            save([record])
            return record
        } catch {
            return nil
        }
    }

    static func importCertificate(
        p12: URL,
        profileURL: URL,
        displayName: String,
        password: String
    ) async throws -> CertificateRecord {
        guard FileManager.default.fileExists(atPath: p12.path),
              FileManager.default.fileExists(atPath: profileURL.path) else {
            throw StoreError.missingFiles
        }
        let profile = try parseProfile(profileURL)
        if let expires = profile.expires, expires <= Date() {
            throw StoreError.expiredProfile
        }
        try await validateP12(p12, password: password)

        let id = UUID()
        let dir = AppPaths.certificateDirectory(id)
        do {
            try FileManager.default.copyItem(at: p12, to: dir.appendingPathComponent("cert.p12"))
            try FileManager.default.copyItem(at: profileURL, to: dir.appendingPathComponent("profile.mobileprovision"))
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("cert.p12").path)
        } catch {
            throw StoreError.copyFailed
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CertificateRecord(
            id: id,
            displayName: trimmed.isEmpty ? profile.name : trimmed,
            profileName: profile.name,
            teamID: profile.teamID,
            appID: profile.appID,
            expires: profile.expires,
            provisionedDevices: profile.devices,
            allDevices: profile.allDevices,
            isBuiltIn: false,
            importedAt: Date()
        )

        var records = load()
        records.append(record)
        save(records)
        return record
    }

    static func delete(_ record: CertificateRecord) {
        var records = load()
        records.removeAll { $0.id == record.id }
        save(records)
        try? FileManager.default.removeItem(at: AppPaths.certificateDirectory(record.id))
    }

    static func parseProfile(_ url: URL) throws -> ProfileInfo {
        guard let data = try? runData("/usr/bin/security", ["cms", "-D", "-i", url.path]),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw StoreError.invalidProfile
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let team = (plist["TeamIdentifier"] as? [String])?.first ?? ""
        return ProfileInfo(
            name: plist["Name"] as? String ?? "Provisioning profile",
            teamID: team,
            appID: entitlements["application-identifier"] as? String ?? "",
            expires: plist["ExpirationDate"] as? Date,
            devices: plist["ProvisionedDevices"] as? [String] ?? [],
            allDevices: (plist["ProvisionsAllDevices"] as? Bool) ?? false
        )
    }

    private static func validateP12(_ p12: URL, password: String) async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ipa-dispatch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let keychain = temp.appendingPathComponent("validate.keychain-db").path
        let keychainPassword = UUID().uuidString

        defer {
            _ = runStatus("/usr/bin/security", ["delete-keychain", keychain])
            try? FileManager.default.removeItem(at: temp)
        }

        _ = await runStatusAsync("/usr/bin/security", ["create-keychain", "-p", keychainPassword, keychain])
        _ = await runStatusAsync("/usr/bin/security", ["set-keychain-settings", "-lut", "300", keychain])
        _ = await runStatusAsync("/usr/bin/security", ["unlock-keychain", "-p", keychainPassword, keychain])

        let importCode = await runStatusAsync("/usr/bin/security", [
            "import", p12.path,
            "-k", keychain,
            "-P", password,
            "-T", "/usr/bin/codesign",
            "-T", "/usr/bin/security",
            "-f", "pkcs12"
        ])
        if importCode != 0 { throw StoreError.wrongPassword }

        let identities = (try? await Shell.capture("/usr/bin/security", ["find-identity", "-p", "codesigning", keychain])) ?? ""
        if !identities.contains("1)") {
            throw StoreError.noIdentity
        }
    }

    private static func runStatus(_ executable: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch { return -1 }
    }

    private static func runStatusAsync(_ executable: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }

    private static func runData(_ executable: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } catch { return nil }
    }
}
