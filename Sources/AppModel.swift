import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [IPAItem] = []
    @Published var devices: [DeviceRecord] = []
    @Published var certificates: [CertificateRecord] = []
    @Published var selectedDeviceID: String?
    @Published var selectedCertificateID: UUID?
    @Published var language: AppLanguage
    @Published var isInstalling = false
    @Published var showPassword = false
    @Published var showLog = false
    @Published var showCertificates = false
    @Published var showImportCertificate = false
    @Published var isImportingCertificate = false
    @Published var importError: String?
    @Published var progress: Double = 0
    @Published var log: [LogEntry] = []
    @Published var itemLogs: [UUID: [LogEntry]] = [:]
    @Published var error: LocalizedMessage?
    @Published var status: LocalizedMessage
    @Published var currentIndex: Int?
    @Published var isDropTargeted = false
    @Published var passwordPurpose: PasswordPurpose = .install
    @Published var signOnlyOutputDir: URL?
    @Published var showURLDownload = false
    @Published var isDownloadingURL = false
    @Published var urlDownloadError: String?

    enum PasswordPurpose { case install, signOnly }

    private var installTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        self.language = AppLanguage(rawValue: saved ?? "") ?? .systemDefault
        self.status = LocalizedMessage("status.ready")
    }

    // MARK: Localization

    func t(_ key: String, _ args: String...) -> String {
        L10n.text(language, key, args: args)
    }

    func t(_ message: LocalizedMessage) -> String {
        L10n.text(language, message)
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
    }

    // MARK: Selection

    var selectedDevice: DeviceRecord? {
        devices.first { $0.udid == selectedDeviceID }
    }

    var selectedCertificate: CertificateRecord? {
        certificates.first { $0.id == selectedCertificateID }
    }

    var compatibleCertificates: [CertificateRecord] {
        guard let device = selectedDevice else { return certificates }
        return certificates.filter { $0.supports(device.udid) }
    }

    var incompatibleCertificates: [CertificateRecord] {
        guard let device = selectedDevice else { return [] }
        return certificates.filter { !$0.supports(device.udid) }
    }

    var orderedCertificates: [CertificateRecord] {
        let rank = Dictionary(uniqueKeysWithValues: devices.enumerated().map { ($1.udid, $0) })
        return certificates.sorted { a, b in
            let ar = a.provisionedDevices.compactMap { rank[$0] }.min() ?? Int.max
            let br = b.provisionedDevices.compactMap { rank[$0] }.min() ?? Int.max
            if ar != br { return ar < br }
            if a.isBuiltIn != b.isBuiltIn { return !a.isBuiltIn }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    var isReading: Bool { items.contains { $0.status == .reading } }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    var canInstall: Bool {
        !isInstalling
            && !items.isEmpty
            && !isReading
            && !items.contains { $0.bundleID.isEmpty }
            && (selectedDevice?.connected ?? false)
            && (selectedCertificate?.valid ?? false)
            && (selectedDevice.map { device in
                selectedCertificate.map { $0.supports(device.udid) } ?? false
            } ?? false)
    }

    var canSignOnly: Bool {
        !isInstalling
            && !items.isEmpty
            && !isReading
            && !items.contains { $0.bundleID.isEmpty }
            && (selectedCertificate?.valid ?? false)
            && (selectedDevice.map { device in
                selectedCertificate.map { $0.supports(device.udid) } ?? false
            } ?? true)
    }

    var installButtonTitle: String {
        if isInstalling { return t("installing") }
        if items.isEmpty { return t("install") }
        if items.count == 1 { return t("installPackage") }
        return t("installPackages", String(items.count))
    }

    var batchSizeLabel: String {
        if totalSize >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(totalSize) / 1_073_741_824)
        }
        return String(format: "%.0f MB", Double(totalSize) / 1_048_576)
    }

    var deviceStateLabel: String {
        guard let device = selectedDevice else { return t("device.none") }
        if device.state.lowercased() == "network" { return t("device.network") }
        if !device.connected { return t("device.notConnected") }
        return t("device.connected")
    }

    // MARK: Bootstrap

    func bootstrap() async {
        certificates = CertificateStore.load()
        await refreshDevices(selecting: nil)
        restoreSelections()
        updateReadyStatus()
    }

    private func restoreSelections() {
        let savedDevice = UserDefaults.standard.string(forKey: "selectedDeviceID")
        let savedCert = UserDefaults.standard.string(forKey: "selectedCertificateID").flatMap(UUID.init(uuidString:))

        if let savedDevice, devices.contains(where: { $0.udid == savedDevice }) {
            selectedDeviceID = savedDevice
        } else {
            selectedDeviceID = devices.first(where: { $0.connected })?.udid ?? devices.first?.udid
        }

        if let savedCert, certificates.contains(where: { $0.id == savedCert }) {
            selectedCertificateID = savedCert
        }
        normalizeCertificateSelection()
        persistSelections()
    }

    func refreshDevices(selecting preferred: String? = nil) async {
        let refreshed = await DeviceStore.refresh()
        let previous = selectedDeviceID
        devices = mergeDevices(refreshed, withCertificateDevices: certificates)
        if let preferred, devices.contains(where: { $0.udid == preferred }) {
            selectedDeviceID = preferred
        } else if let previous, devices.contains(where: { $0.udid == previous }) {
            selectedDeviceID = previous
        } else {
            selectedDeviceID = devices.first(where: { $0.connected })?.udid ?? devices.first?.udid
        }
        normalizeCertificateSelection()
        persistSelections()
        updateReadyStatus()
    }

    private func mergeDevices(_ refreshed: [DeviceRecord], withCertificateDevices certs: [CertificateRecord]) -> [DeviceRecord] {
        var map = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.udid, $0) })
        for cert in certs where !cert.allDevices {
            for udid in cert.provisionedDevices where map[udid] == nil {
                map[udid] = DeviceRecord(
                    udid: udid,
                    name: "Device \(udid.suffix(4))",
                    state: "disconnected",
                    connected: false,
                    lastSeen: Date.distantPast
                )
            }
        }
        return map.values.sorted {
            if $0.connected != $1.connected { return $0.connected && !$1.connected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func normalizeCertificateSelection() {
        guard let device = selectedDevice else {
            if selectedCertificateID == nil { selectedCertificateID = certificates.first?.id }
            return
        }
        if let selected = selectedCertificate, selected.supports(device.udid) { return }
        selectedCertificateID = certificates.first(where: { $0.supports(device.udid) && $0.valid })?.id
            ?? certificates.first(where: { $0.supports(device.udid) })?.id
    }

    func selectDevice(_ id: String) {
        guard devices.contains(where: { $0.udid == id }) else { return }
        selectedDeviceID = id
        normalizeCertificateSelection()
        persistSelections()
        error = nil
        updateReadyStatus()
    }

    func selectCertificate(_ id: UUID) {
        guard let cert = certificates.first(where: { $0.id == id }) else { return }
        selectedCertificateID = id
        if let device = selectedDevice, !cert.supports(device.udid) {
            if let matching = devices.first(where: { cert.supports($0.udid) && $0.connected })
                ?? devices.first(where: { cert.supports($0.udid) }) {
                selectedDeviceID = matching.udid
            } else {
                error = LocalizedMessage("error.incompatible")
            }
        }
        persistSelections()
        updateReadyStatus()
    }

    private func persistSelections() {
        UserDefaults.standard.set(selectedDeviceID, forKey: "selectedDeviceID")
        UserDefaults.standard.set(selectedCertificateID?.uuidString, forKey: "selectedCertificateID")
    }

    // MARK: Certificate management

    func importCertificate(p12: URL, profile: URL, name: String, password: String) async {
        isImportingCertificate = true
        importError = nil
        do {
            let record = try await CertificateStore.importCertificate(
                p12: p12,
                profileURL: profile,
                displayName: name,
                password: password
            )
            certificates = CertificateStore.load()
            devices = mergeDevices(DeviceStore.known(), withCertificateDevices: certificates)
            if let matching = devices.first(where: { record.supports($0.udid) && $0.connected })
                ?? devices.first(where: { record.supports($0.udid) }) {
                selectedDeviceID = matching.udid
            }
            selectedCertificateID = record.id
            persistSelections()
            showImportCertificate = false
            showCertificates = false
            importError = nil
            updateReadyStatus()
        } catch {
            importError = error.localizedDescription
        }
        isImportingCertificate = false
    }

    func deleteCertificate(_ record: CertificateRecord) {
        guard !record.isBuiltIn else { return }
        CertificateStore.delete(record)
        certificates = CertificateStore.load()
        if selectedCertificateID == record.id {
            selectedCertificateID = nil
            normalizeCertificateSelection()
        }
        devices = mergeDevices(DeviceStore.known(), withCertificateDevices: certificates)
        persistSelections()
        updateReadyStatus()
    }

    func openCertificateManager() {
        showCertificates = true
    }

    func openImportCertificate() {
        importError = nil
        showImportCertificate = true
    }

    // MARK: IPA list

    func chooseFiles() {
        guard !isInstalling else { return }
        let panel = NSOpenPanel()
        panel.title = t("choose")
        panel.prompt = t("common.add")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    func startURLDownload(_ raw: String) {
        guard !isInstalling, !isDownloadingURL else { return }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            urlDownloadError = t("error.url")
            return
        }
        let name = url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard name.lowercased().hasSuffix(".ipa"), !name.isEmpty else {
            urlDownloadError = t("error.url")
            return
        }
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/IPA Dispatch Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        var dest = downloads.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            dest = downloads.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).ipa")
        }
        urlDownloadError = nil
        isDownloadingURL = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await ProcessRunner.run(
                    executable: "/usr/bin/curl",
                    arguments: ["--fail", "--location", "--retry", "2", "--connect-timeout", "30", "--silent", "--show-error", "--output", dest.path, url.absoluteString],
                    environment: ProcessInfo.processInfo.environment
                ) { [weak self] line, isError in
                    DispatchQueue.main.async {
                        guard let self, !line.isEmpty else { return }
                        self.append(.init(text: line, isError: isError), itemID: nil)
                    }
                }
                await MainActor.run {
                    self.isDownloadingURL = false
                    guard code == 0, FileManager.default.fileExists(atPath: dest.path) else {
                        self.urlDownloadError = self.t("error.download")
                        return
                    }
                    self.showURLDownload = false
                    self.add([dest])
                    self.status = LocalizedMessage("status.reading")
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingURL = false
                    self.urlDownloadError = error.localizedDescription
                }
            }
        }
    }

    func chooseICloudFiles() {
        guard !isInstalling else { return }
        let panel = NSOpenPanel()
        panel.title = t("icloud.import")
        panel.prompt = t("common.add")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: drive.path) {
            panel.directoryURL = drive
        }
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    func add(_ urls: [URL]) {
        guard !isInstalling else { return }
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        var addedAny = false
        for url in urls {
            let normalized = url.standardizedFileURL
            guard normalized.pathExtension.lowercased() == "ipa",
                  !existing.contains(normalized.path),
                  !items.contains(where: { $0.url.standardizedFileURL == normalized }) else { continue }
            let item = IPAItem(url: normalized)
            items.append(item)
            addedAny = true
            Task {
                let inspected = await IPAInspector.inspect(normalized, id: item.id)
                if let index = items.firstIndex(where: { $0.id == inspected.id }) {
                    items[index] = inspected
                }
                updateReadyStatus()
            }
        }
        if addedAny {
            error = nil
            status = LocalizedMessage("status.reading")
        }
    }

    func remove(_ item: IPAItem) {
        guard !isInstalling else { return }
        items.removeAll { $0.id == item.id }
        itemLogs.removeValue(forKey: item.id)
        updateReadyStatus()
    }

    func clear() {
        guard !isInstalling else { return }
        items.removeAll()
        itemLogs.removeAll()
        progress = 0
        updateReadyStatus()
    }

    private func updateReadyStatus() {
        if items.isEmpty {
            status = LocalizedMessage(selectedDevice?.connected == true ? "status.ready" : "status.connect")
            return
        }
        if isReading {
            status = LocalizedMessage("status.reading")
            return
        }
        if items.contains(where: { $0.status == .failed }) {
            status = LocalizedMessage("status.someFailedRead")
            return
        }
        status = items.count == 1
            ? LocalizedMessage("status.packageReady")
            : LocalizedMessage("status.packagesReady", String(items.count))
    }

    // MARK: Install

    func requestInstall() {
        guard !isInstalling else { return }
        guard let device = selectedDevice, device.connected else {
            error = LocalizedMessage("error.device")
            return
        }
        guard let cert = selectedCertificate, cert.valid, cert.supports(device.udid) else {
            error = LocalizedMessage(certificates.isEmpty ? "error.profile" : "error.incompatible")
            return
        }
        guard !items.isEmpty else {
            error = LocalizedMessage("error.noPackages")
            return
        }
        if let insufficient = insufficientDiskMessage() {
            error = LocalizedMessage("error.disk", insufficient)
            return
        }
        guard !isReading, !items.contains(where: { $0.bundleID.isEmpty }) else {
            error = LocalizedMessage("error.reading")
            return
        }
        error = nil
        passwordPurpose = .install
        showPassword = true
    }

    func requestSignOnly() {
        guard !isInstalling else { return }
        guard let cert = selectedCertificate, cert.valid else {
            error = LocalizedMessage(certificates.isEmpty ? "error.profile" : "error.incompatible")
            return
        }
        if let device = selectedDevice, !cert.supports(device.udid) {
            error = LocalizedMessage("error.incompatible")
            return
        }
        guard !items.isEmpty else {
            error = LocalizedMessage("error.noPackages")
            return
        }
        guard !isReading, !items.contains(where: { $0.bundleID.isEmpty }) else {
            error = LocalizedMessage("error.reading")
            return
        }
        let panel = NSOpenPanel()
        panel.title = t("sign.chooseOutput")
        panel.prompt = t("common.done")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        signOnlyOutputDir = dir
        error = nil
        passwordPurpose = .signOnly
        showPassword = true
    }

    func chooseSignedIPAFiles() {
        guard !isInstalling else { return }
        guard let device = selectedDevice, device.connected else {
            error = LocalizedMessage("error.device")
            return
        }
        let panel = NSOpenPanel()
        panel.title = t("install.signed")
        panel.prompt = t("install")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            await self?.runInstallSigned(urls: urls, device: device)
        }
    }

    func submitPassword(_ password: String) {
        switch passwordPurpose {
        case .install:
            beginInstall(password: password)
        case .signOnly:
            beginSignOnly(password: password)
        }
    }

    private func beginSignOnly(password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = LocalizedMessage("error.password")
            return
        }
        guard !isInstalling, let dir = signOnlyOutputDir else { return }
        showPassword = false
        error = nil
        installTask = Task { [weak self] in
            await self?.runSignOnly(password: trimmed, outputDir: dir)
        }
    }

    private func runSignOnly(password: String, outputDir: URL) async {
        let targets = items
        guard let cert = selectedCertificate, !targets.isEmpty else { return }
        isInstalling = true
        showLog = true
        log.removeAll()
        itemLogs.removeAll()
        progress = 0
        currentIndex = nil
        status = LocalizedMessage("status.preparing")

        var env = ProcessInfo.processInfo.environment
        let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (env["PATH"].map { "\(basePath):\($0)" }) ?? basePath
        env["P12_PASSWORD"] = password

        if let device = selectedDevice, !cert.supports(device.udid) {
            error = LocalizedMessage("error.incompatible")
            isInstalling = false
            return
        }
        let udid = selectedDevice?.udid
            ?? cert.provisionedDevices.first
            ?? "00000000-0000000000000000"
        var failed = 0

        for (index, item) in targets.enumerated() {
            guard index < items.count else { continue }
            currentIndex = index
            items[index].status = .running
            items[index].message = nil
            itemLogs[item.id] = []
            status = LocalizedMessage("status.signingPackage", item.name)
            progress = Double(index) / Double(targets.count)
            append(.init(text: "── sign only \(index + 1)/\(targets.count)  \(item.url.lastPathComponent)", isError: false), itemID: item.id)

            let base = item.url.deletingPathExtension().lastPathComponent
            let out = outputDir.appendingPathComponent("\(base)-signed.ipa")
            let arguments = [
                AppPaths.signer.path,
                "-i", item.url.path,
                "-c", cert.p12URL.path,
                "-m", cert.profileURL.path,
                "-u", udid,
                "-o", out.path,
                "--no-install",
                "--cleanup"
            ]

            var exitCode: Int32 = 1
            do {
                exitCode = try await ProcessRunner.run(
                    executable: "/bin/zsh",
                    arguments: arguments,
                    environment: env
                ) { [weak self] line, isError in
                    DispatchQueue.main.async {
                        self?.append(.init(text: line, isError: isError), itemID: item.id)
                    }
                }
            } catch {
                append(.init(text: "Failed to launch signer: \(error.localizedDescription)", isError: true), itemID: item.id)
            }

            if exitCode == 0 {
                items[index].status = .done
                items[index].message = out.path
                status = LocalizedMessage("status.signed", out.lastPathComponent)
            } else {
                failed += 1
                items[index].status = .failed
                items[index].message = t("status.failed", String(exitCode))
                status = LocalizedMessage("status.failed", String(exitCode))
            }
            progress = Double(index + 1) / Double(targets.count)
        }

        currentIndex = nil
        isInstalling = false
        if failed == 0 {
            status = LocalizedMessage("status.allSigned", String(targets.count))
            progress = 1
        } else {
            status = LocalizedMessage("status.finishedFailed", String(failed))
        }
    }

    private func runInstallSigned(urls: [URL], device: DeviceRecord) async {
        isInstalling = true
        showLog = true
        log.removeAll()
        itemLogs.removeAll()
        progress = 0
        status = LocalizedMessage("status.preparing")

        var env = ProcessInfo.processInfo.environment
        let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (env["PATH"].map { "\(basePath):\($0)" }) ?? basePath
        var failed = 0

        for (index, url) in urls.enumerated() {
            currentIndex = index
            status = LocalizedMessage("status.installingPackage", url.lastPathComponent)
            progress = Double(index) / Double(urls.count)
            append(.init(text: "── install signed \(index + 1)/\(urls.count)  \(url.lastPathComponent)", isError: false), itemID: nil)
            var code: Int32 = 1
            do {
                code = try await ProcessRunner.run(
                    executable: "/usr/bin/xcrun",
                    arguments: ["devicectl", "device", "install", "app", "--device", device.udid, url.path],
                    environment: env
                ) { [weak self] line, isError in
                    DispatchQueue.main.async { self?.append(.init(text: line, isError: isError), itemID: nil) }
                }
            } catch {
                append(.init(text: "Failed to launch devicectl: \(error.localizedDescription)", isError: true), itemID: nil)
            }
            if code != 0 { failed += 1 }
            progress = Double(index + 1) / Double(urls.count)
        }
        currentIndex = nil
        isInstalling = false
        status = failed == 0
            ? LocalizedMessage("status.installed")
            : LocalizedMessage("status.finishedFailed", String(failed))
    }

    private func insufficientDiskMessage() -> String? {
        let needed = items.reduce(Int64(0)) { $0 + max($1.size, 0) }
        guard needed > 0 else { return nil }
        let volume = (items.first?.url ?? URL(fileURLWithPath: "/"))
        guard let free = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        // Extraction + signed IPA + install cache: reserve two times the source.
        let required = needed * 2
        guard free < required else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return "\(formatter.string(fromByteCount: needed)) source, \(formatter.string(fromByteCount: free)) free; \(formatter.string(fromByteCount: required)) required"
    }

    func beginInstall(password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = LocalizedMessage("error.password")
            return
        }
        guard !isInstalling else { return }
        showPassword = false
        error = nil
        installTask = Task { [weak self] in
            await self?.runInstall(password: trimmed)
        }
    }

    private func runInstall(password: String) async {
        let targets = items
        guard let device = selectedDevice, let cert = selectedCertificate, !targets.isEmpty else { return }

        isInstalling = true
        showLog = true
        log.removeAll()
        itemLogs.removeAll()
        progress = 0
        currentIndex = nil
        status = LocalizedMessage("status.preparing")

        var env = ProcessInfo.processInfo.environment
        let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (env["PATH"].map { "\(basePath):\($0)" }) ?? basePath
        env["P12_PASSWORD"] = password

        var failedCount = 0
        for (index, item) in targets.enumerated() {
            guard index < items.count else { continue }
            currentIndex = index
            items[index].status = .running
            items[index].message = nil
            itemLogs[item.id] = []
            status = LocalizedMessage("status.signingPackage", item.name)
            progress = Double(index) / Double(targets.count)
            append(.init(text: "── \(index + 1)/\(targets.count)  \(item.url.lastPathComponent)", isError: false), itemID: item.id)

            let arguments = [
                AppPaths.signer.path,
                "-i", item.url.path,
                "-c", cert.p12URL.path,
                "-m", cert.profileURL.path,
                "-u", device.udid,
                "--cleanup"
            ]

            var exitCode: Int32 = 1
            do {
                exitCode = try await ProcessRunner.run(
                    executable: "/bin/zsh",
                    arguments: arguments,
                    environment: env
                ) { [weak self] line, isError in
                    DispatchQueue.main.async {
                        self?.handle(line: line, isError: isError, index: index)
                    }
                }
            } catch {
                append(.init(text: "Failed to launch signer: \(error.localizedDescription)", isError: true), itemID: item.id)
            }

            if exitCode == 0 {
                items[index].status = .done
                status = LocalizedMessage("status.installed")
            } else {
                failedCount += 1
                items[index].status = .failed
                items[index].message = t("status.failed", String(exitCode))
                status = LocalizedMessage("status.failed", String(exitCode))
            }
            progress = Double(index + 1) / Double(targets.count)
        }

        currentIndex = nil
        isInstalling = false
        if failedCount == 0 {
            status = LocalizedMessage("status.allInstalled")
            progress = 1
        } else {
            status = LocalizedMessage("status.finishedFailed", String(failedCount))
        }
        await refreshDevices(selecting: device.udid)
    }

    private func handle(line: String, isError: Bool, index: Int) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = LogEntry(text: trimmed, isError: isError)
        let itemID = index < items.count ? items[index].id : nil
        append(entry, itemID: itemID)

        if trimmed.hasPrefix("Installed bundle ID: ") {
            let installed = String(trimmed.dropFirst("Installed bundle ID: ".count))
            guard index < items.count else { return }
            items[index].installedBundleID = installed
            if installed != items[index].bundleID {
                items[index].copiedForConflict = true
                items[index].message = t("sideCopy", installed)
            }
        }
        if trimmed.hasPrefix("Trying bundle ID: ") {
            guard index < items.count else { return }
            let trying = String(trimmed.dropFirst("Trying bundle ID: ".count))
            items[index].message = t("trying", trying)
        }
        if isError && trimmed.localizedCaseInsensitiveContains("error") {
            error = LocalizedMessage("error.signer", trimmed)
        }
    }

    private func append(_ entry: LogEntry, itemID: UUID? = nil) {
        log.append(entry)
        if log.count > 700 {
            log.removeFirst(log.count - 700)
        }
        guard let itemID else { return }
        var entries = itemLogs[itemID] ?? []
        entries.append(entry)
        if entries.count > 400 {
            entries.removeFirst(entries.count - 400)
        }
        itemLogs[itemID] = entries
    }
}
