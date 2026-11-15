import Foundation

struct DeviceStateSnapshot {
    let udid: String
    let name: String
    let state: String
    let connected: Bool
}

/// 设备在线状态的纯逻辑层：不执行命令、不读写磁盘，便于单元测试。
/// DeviceStore 只负责调用 devicectl、合并历史记录和持久化。
enum DeviceState {
    /// 只认 "available*" / "connected*"。
    /// 不能用子串包含："unavailable" 含 "available"，"disconnected" 含 "connected"。
    static func isOnline(_ state: String) -> Bool {
        let value = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("available") || value.hasPrefix("connected")
    }

    static func normalized(_ raw: String?, pairingState: String?) -> String {
        var state = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isEmpty { state = "disconnected" }
        if state == "available", pairingState?.lowercased() == "paired" {
            state = "available (paired)"
        }
        return state
    }

    /// 解析 `devicectl list devices --json-output` 的内容。
    /// 返回 nil 表示不是预期的 JSON 结构，调用方应回退到表格解析。
    static func parseJSON(_ data: Data) -> [DeviceStateSnapshot]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]] else { return nil }

        var snapshots: [DeviceStateSnapshot] = []
        for device in devices {
            // 新版 Xcode 把字段放在 properties 下；三个旧字典已标 deprecated
            // 但仍会输出，两种都接受，兼容不同 Xcode 版本。
            let props = device["properties"] as? [String: Any] ?? [:]
            let hardware = props["hardware"] as? [String: Any]
                ?? device["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = props["connection"] as? [String: Any]
                ?? device["connectionProperties"] as? [String: Any] ?? [:]
            let softwareState = props["state"] as? [String: Any] ?? [:]
            let legacy = device["deviceProperties"] as? [String: Any] ?? [:]

            guard let udid = hardware["udid"] as? String, !udid.isEmpty,
                  (hardware["reality"] as? String)?.lowercased() == "physical" else { continue }

            let name = softwareState["name"] as? String
                ?? legacy["name"] as? String
                ?? hardware["marketingName"] as? String
                ?? "iPhone"
            let state = normalized(
                (connection["state"] as? String) ?? (connection["tunnelState"] as? String),
                pairingState: connection["pairingState"] as? String
            )
            snapshots.append(DeviceStateSnapshot(udid: udid,
                                                 name: name,
                                                 state: state,
                                                 connected: isOnline(state)))
        }
        return snapshots
    }

    /// 解析 `devicectl list devices` 的表格输出，列间为 2+ 空格：
    /// name | UDID (UDID) | state | model | reality
    static func parseTable(_ output: String) -> [DeviceStateSnapshot] {
        let pattern = try? NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{8,}")
        var snapshots: [DeviceStateSnapshot] = []
        for line in output.split(separator: "\n").map(String.init) {
            guard let regex = pattern,
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range, in: line) else { continue }

            let tail = String(line[range.upperBound...])
            let columns = tail
                .replacingOccurrences(of: "\\s{2,}", with: "|", options: .regularExpression)
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard columns.count >= 4,
                  columns.last?.lowercased() == "physical" else { continue }

            let udid = String(line[range])
            let name = String(line[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let state = normalized(columns[1], pairingState: nil)
            snapshots.append(DeviceStateSnapshot(udid: udid,
                                                 name: name.isEmpty ? "iPhone" : name,
                                                 state: state,
                                                 connected: isOnline(state)))
        }
        return snapshots
    }
}
