import Foundation

enum DeviceStore {
    static func known() -> [DeviceRecord] {
        guard let data = try? Data(contentsOf: AppPaths.devicesFile),
              let records = try? JSONDecoder().decode([DeviceRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [DeviceRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: AppPaths.devicesFile, options: .atomic)
        }
    }

    static func refresh() async -> [DeviceRecord] {
        let previous = known()
        let current = await fetchSnapshots().map {
            DeviceRecord(udid: $0.udid,
                         name: $0.name,
                         state: $0.state,
                         connected: $0.connected,
                         lastSeen: Date())
        }

        var map = Dictionary(uniqueKeysWithValues: previous.map { ($0.udid, $0) })
        for record in current {
            map[record.udid] = record
        }
        // A device from the saved list that is absent now should not look connected.
        let currentIDs = Set(current.map { $0.udid })
        for (udid, var record) in map where !currentIDs.contains(udid) {
            record.connected = false
            record.state = "disconnected"
            map[udid] = record
        }

        let merged = map.values.sorted {
            if $0.connected != $1.connected { return $0.connected && !$1.connected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        save(merged)
        return merged
    }

    // MARK: - Reading devicectl

    /// 优先结构化输出；解析失败或没有真机时回退到表格输出。
    /// 所有判定逻辑都在 DeviceState（纯函数，见 Tests/）。
    private static func fetchSnapshots() async -> [DeviceStateSnapshot] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipa-dispatch-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try? await Shell.capture("/usr/bin/xcrun",
                                     ["devicectl", "list", "devices", "--json-output", url.path])
        if let data = try? Data(contentsOf: url),
           let parsed = DeviceState.parseJSON(data), !parsed.isEmpty {
            return parsed
        }
        guard let output = try? await Shell.capture("/usr/bin/xcrun",
                                                    ["devicectl", "list", "devices"]) else { return [] }
        return DeviceState.parseTable(output)
    }
}
