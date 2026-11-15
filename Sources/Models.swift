import Foundation
import SwiftUI

enum InstallStatus: String, Equatable {
    case reading
    case queued
    case running
    case done
    case failed

    var label: String {
        switch self {
        case .reading: return "READING"
        case .queued: return "QUEUED"
        case .running: return "SIGNING"
        case .done: return "DONE"
        case .failed: return "FAILED"
        }
    }
}

struct IPAItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var name: String
    var bundleID: String
    var version: String
    var size: Int64
    var status: InstallStatus
    var installedBundleID: String?
    var message: String?
    var copiedForConflict: Bool

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.bundleID = ""
        self.version = ""
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        self.status = .reading
        self.installedBundleID = nil
        self.message = nil
        self.copiedForConflict = false
    }

    var sizeLabel: String {
        if size >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(size) / 1_073_741_824)
        }
        return String(format: "%.0f MB", Double(size) / 1_048_576)
    }

    var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.first.map(String.init) ?? "?").uppercased()
    }
}

struct DeviceInfo: Equatable {
    var name: String = "No iPhone"
    var udid: String = ""
    var state: String = "disconnected"
    var osVersion: String = ""

    var connected: Bool {
        let value = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("available") || value.hasPrefix("connected")
    }
}

struct CertificateInfo: Equatable {
    var profileName: String = ""
    var teamID: String = ""
    var appID: String = ""
    var expires: Date?
    var valid: Bool = false

    var expiryLabel: String {
        guard let expires else { return "UNKNOWN" }
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: expires)
    }

    var teamLabel: String { teamID.isEmpty ? "UNKNOWN TEAM" : teamID }
    var appIDShort: String { appID.isEmpty ? "UNKNOWN APP ID" : appID }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

enum AppPaths {
    static var resources: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    static var signer: URL {
        resources.appendingPathComponent("sign-ios-ipa.sh")
    }

    static var bundledP12: URL {
        resources.appendingPathComponent("ipa-signing/bundled/cert.p12")
    }

    static var bundledProfile: URL {
        resources.appendingPathComponent("ipa-signing/bundled/profile.mobileprovision")
    }

    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("IPA Dispatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var certificatesRoot: URL {
        let url = support.appendingPathComponent("Certificates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var certificateIndex: URL {
        support.appendingPathComponent("certificates.json")
    }

    static var devicesFile: URL {
        support.appendingPathComponent("devices.json")
    }

    static func certificateDirectory(_ id: UUID) -> URL {
        let url = certificatesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct DeviceRecord: Identifiable, Codable, Equatable {
    var udid: String
    var name: String
    var state: String
    var connected: Bool
    var lastSeen: Date

    var id: String { udid }
    var stateLabel: String { connected ? state : "disconnected" }
}

struct CertificateRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var profileName: String
    var teamID: String
    var appID: String
    var expires: Date?
    var provisionedDevices: [String]
    var allDevices: Bool
    var isBuiltIn: Bool
    var importedAt: Date

    var p12URL: URL { AppPaths.certificateDirectory(id).appendingPathComponent("cert.p12") }
    var profileURL: URL { AppPaths.certificateDirectory(id).appendingPathComponent("profile.mobileprovision") }

    var expiryLabel: String {
        guard let expires else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: expires)
    }

    var valid: Bool { expires.map { $0 > Date() } ?? false }

    func supports(_ udid: String) -> Bool {
        allDevices || provisionedDevices.contains(udid)
    }
}

struct ProfileInfo {
    var name: String
    var teamID: String
    var appID: String
    var expires: Date?
    var devices: [String]
    var allDevices: Bool
}
