import Foundation

/// Waits for a file selected from iCloud Drive to become locally available.
/// Large IPAs can stay as placeholders until the app asks iCloud to download
/// them; reading them directly through unzip would otherwise fail.
enum ICloudFile {
    enum DownloadError: LocalizedError {
        case timeout

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "iCloud download timed out. Download the IPA in Finder, then try again."
            }
        }
    }

    static func ensureAvailable(_ url: URL) async throws -> URL {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else {
            return url
        }
        if values.ubiquitousItemDownloadingStatus == .current {
            return url
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        // 30 minutes; a 10 GB IPA can take a while on a slow connection.
        for _ in 0..<3_600 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if status?.ubiquitousItemDownloadingStatus == .current {
                return url
            }
        }
        throw DownloadError.timeout
    }
}
