import Foundation

@main
struct DeviceStateTests {
    static func main() {
        var total = 0
        var failures: [String] = []

        func expect<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
            total += 1
            if actual == expected {
                print("  ok   \(label)")
            } else {
                print("  FAIL \(label): got \(actual), expected \(expected)")
                failures.append(label)
            }
        }

        print("isOnline — 在线白名单 / 离线陷阱")
        for (raw, expected) in [
            ("available", true),
            ("available (paired)", true),
            ("connected", true),
            ("AVAILABLE", true),
            ("  connected  ", true),
            ("unavailable", false),
            ("disconnected", false),
            ("shutdown", false),
            ("booted", false),
            ("", false)
        ] {
            expect("isOnline(\"\(raw)\")", DeviceState.isOnline(raw), expected)
        }

        print("normalized — 缺失状态与配对语义")
        expect("nil", DeviceState.normalized(nil, pairingState: nil), "disconnected")
        expect("空白", DeviceState.normalized("  ", pairingState: nil), "disconnected")
        expect("大写 available + paired",
               DeviceState.normalized("AVAILABLE", pairingState: "paired"), "available (paired)")
        expect("unavailable 不因 paired 变成在线文案",
               DeviceState.normalized("unavailable", pairingState: "paired"), "unavailable")

        print("parseJSON — 新版 properties 字段")
        let modern: [String: Any] = ["result": ["devices": [
            ["properties": [
                "hardware": ["udid": "00000000-0000000000000001", "reality": "physical",
                             "marketingName": "iPhone 15 Pro Max"],
                "connection": ["state": "unavailable", "pairingState": "paired"],
                "state": ["name": "iPhone 15 Pro Max"]
            ]],
            ["properties": [
                "hardware": ["udid": "00008120-001A2B3C4D5E6F70", "reality": "physical"],
                "connection": ["state": "available", "pairingState": "paired"],
                "state": ["name": "My iPhone"]
            ]],
            ["properties": [
                "hardware": ["udid": "16BDC05D-FB42", "reality": "simulated"],
                "connection": ["state": "shutdown"]
            ]]
        ]]]
        let modernData = try! JSONSerialization.data(withJSONObject: modern)
        let modernRows = DeviceState.parseJSON(modernData)
        expect("只收 physical 真机", modernRows?.count ?? -1, 2)
        expect("离线设备 state", modernRows?.first?.state ?? "", "unavailable")
        expect("离线设备 connected", modernRows?.first?.connected ?? true, false)
        expect("离线设备名称", modernRows?.first?.name ?? "", "iPhone 15 Pro Max")
        expect("在线设备 state", modernRows?.last?.state ?? "", "available (paired)")
        expect("在线设备 connected", modernRows?.last?.connected ?? false, true)

        print("parseJSON — 旧版 deprecated 字段兼容")
        let legacy: [String: Any] = ["result": ["devices": [
            ["hardwareProperties": ["udid": "00008120-001A2B3C4D5E6F70", "reality": "physical"],
             "deviceProperties": ["name": "Legacy iPhone"],
             "connectionProperties": ["tunnelState": "connected"]]
        ]]]
        let legacyData = try! JSONSerialization.data(withJSONObject: legacy)
        let legacyRows = DeviceState.parseJSON(legacyData)
        expect("旧字段可解析", legacyRows?.count ?? -1, 1)
        expect("旧字段名称", legacyRows?.first?.name ?? "", "Legacy iPhone")
        expect("旧字段 state", legacyRows?.first?.state ?? "", "connected")
        expect("旧字段 connected", legacyRows?.first?.connected ?? false, true)

        print("parseJSON — 无效输入回退")
        expect("乱码返回 nil", DeviceState.parseJSON(Data("nope".utf8)) == nil, true)
        expect("空 result 返回空数组",
               DeviceState.parseJSON(Data("{\"result\":{\"devices\":[]}}".utf8))?.count ?? -1, 0)

        print("parseTable — 表格回退路径")
        let table = """
        Name                           Hostname   Identifier                                    State         Model                                     Reality
        ----------------------------   --------   -------------------------------------------   -----------   ---------------------------------------   ---------
        iPhone 15 Pro Max                         00000000-0000000000000001 (UDID)              unavailable   iPhone 15 Pro Max (iPhone16,2)            physical
        My iPhone                                 00008120-001A2B3C4D5E6F70 (UDID)              available (paired)   iPhone 15 Pro (iPhone15,3)          physical
        iPhone 17                                 16BDC05D-FB42-4170-A1CE-57E5AD0DBB83 (UDID)   shutdown      iPhone 17 (iPhone18,3)                    simulated
        """
        let rows = DeviceState.parseTable(table)
        expect("表头/分隔线/模拟器被过滤", rows.count, 2)
        expect("表格离线 state", rows.first?.state ?? "", "unavailable")
        expect("表格离线 connected", rows.first?.connected ?? true, false)
        expect("表格在线 state", rows.last?.state ?? "", "available (paired)")
        expect("表格在线 connected", rows.last?.connected ?? false, true)
        expect("表格 UDID", rows.first?.udid ?? "", "00000000-0000000000000001")

        print("merge — JSON 旧状态与表格在线状态合并")
        let staleJSON = [DeviceStateSnapshot(udid: "00000000-0000000000000001",
                                             name: "iPhone",
                                             state: "disconnected",
                                             connected: false)]
        let freshTable = [DeviceStateSnapshot(udid: "00000000-0000000000000001",
                                              name: "iPhone",
                                              state: "available (paired)",
                                              connected: true)]
        let merged = DeviceState.merge(staleJSON, freshTable)
        expect("合并数量", merged.count, 1)
        expect("合并后在线", merged.first?.connected ?? false, true)
        expect("合并后 state", merged.first?.state ?? "", "available (paired)")

        print("")
        if failures.isEmpty {
            print("全部 \(total) 项断言通过。")
        } else {
            print("\(failures.count)/\(total) 项失败：\(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}
