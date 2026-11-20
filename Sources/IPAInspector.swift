import Foundation

enum IPAInspector {
    static func inspect(_ url: URL, id: UUID? = nil) async -> IPAItem {
        var item = IPAItem(id: id ?? UUID(), url: url)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let localURL = try await ICloudFile.ensureAvailable(url)
            if let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                item.size = Int64(size)
            }
            let listing = try await Shell.capture("/usr/bin/unzip", ["-Z1", localURL.path])
            let lines = listing.split(separator: "\n").map(String.init)
            guard let infoPath = lines.first(where: { line in
                let parts = line.split(separator: "/")
                return parts.count == 3
                    && parts[0] == "Payload"
                    && parts[1].hasSuffix(".app")
                    && parts[2] == "Info.plist"
            }) else {
                item.status = .failed
                item.message = "No Payload/*.app/Info.plist found."
                return item
            }
            let data = try await Shell.captureData("/usr/bin/unzip", ["-p", localURL.path, infoPath])
            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                item.status = .failed
                item.message = "Could not read Info.plist."
                return item
            }

            let display = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            item.name = display
            item.bundleID = plist["CFBundleIdentifier"] as? String ?? ""
            item.version = plist["CFBundleShortVersionString"] as? String
                ?? plist["CFBundleVersion"] as? String
                ?? ""
            if item.bundleID.isEmpty {
                item.status = .failed
                item.message = "Missing CFBundleIdentifier."
            } else {
                item.status = .queued
            }
        } catch {
            item.status = .failed
            item.message = error.localizedDescription
        }
        return item
    }
}
