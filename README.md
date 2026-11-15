# IPA Dispatch

`一键安装IPA.command` 的 macOS 图形版。支持中英文、多个 IPA、多个设备、多张证书，并可按描述文件自动匹配设备。

## 功能

- 拖入/多选多个 IPA，按列表顺序安装
- 中英文界面切换（右上角「中 / EN」）
- 左侧设备/证书栏，多设备、多证书一目了然
- 多设备：从顶部设备菜单选择目标 iPhone
- 多证书：导入 `.p12` + `.mobileprovision`，在证书管理器中切换
- 证书与设备自动关联：从描述文件的 `ProvisionedDevices` 读取设备，只允许选择兼容的证书
- 冲突 bundle ID 自动安装为 `.sideload1/2/...` 副本
- p12 密码每次安装时输入，不写入磁盘
- 每个 IPA 内置可展开/折叠的日志，失败自动展开，支持复制
- 逐项状态、失败不中断后续 IPA
- 内置一份证书作为初始默认，可继续导入自己的证书

## 使用

1. 打开 `dist/IPA-Dispatch.dmg`，把 `IPA Dispatch.app` 拖到 Applications。
2. 连接 iPhone，解锁并信任这台 Mac。
3. 左侧「设备」列表选择目标 iPhone。
4. 左侧「证书」列表选择兼容证书，或点右侧「+」导入证书。
5. 拖入 IPA，点安装，输入 p12 密码。

### 导入证书

在证书菜单或证书管理器里选择：

- `.p12` 证书文件
- 对应的 `.mobileprovision` 描述文件
- 显示名称
- p12 密码（仅用于本次验证，不保存）

导入时会验证：

- p12 密码和私钥是否可用
- 描述文件是否过期
- 描述文件包含哪些设备
- 证书与描述文件的团队/App ID

证书会复制到：

```text
~/Library/Application Support/IPA Dispatch/Certificates/
```

## 多设备 / 多证书

- 设备列表来自 `xcrun devicectl list devices --json-output`，按 `properties.connection.state` 判断是否在线（只认 `available` / `connected`，`unavailable` 不算已连接），只收录 `physical` 真机；`--json-output` 不可用时回退到表格输出的状态列。同时保留曾连接过的设备，离线时显示为「未连接」。
- 证书按描述文件的 `ProvisionedDevices` 关联设备。
- 选择设备后，证书菜单只允许选择包含该设备的证书。
- 选择某张证书时，如果当前设备不在它的描述文件中，会自动切换到该证书支持的设备。

## 注意

- App 内置了一份初始证书；App 内部和 Application Support 都包含 p12，请勿把 App/DMG 发给别人。
- 描述文件有效期以实际证书为准；共享证书可能提前吊销。
- 当前是本地 ad-hoc 签名，未做 Apple 公证；如果 Gatekeeper 拦截，右键 App → 打开。
- 换手机/换证书不需要重新打包 App，直接在界面导入/选择。
- 6.8 GB 游戏建议 USB-C 连接安装。

## 重新构建

```bash
cd ipa-dispatch
./build.sh
```

要求：Xcode / Swift 6 toolchain、macOS 14+。

### 运行测试

```bash
./run-tests.sh
```

只编译设备状态的纯逻辑层（`Sources/DeviceState.swift`）与 `Tests/DeviceStateTests.swift`，不需要连接 iPhone，覆盖：

- 在线白名单 `available` / `connected`，以及 `unavailable` / `disconnected` 这两个子串陷阱
- 新旧两代 `devicectl --json-output` 字段（`properties.*` 与 deprecated 字典）
- 表格输出回退解析、表头/分隔线/模拟器过滤
- 缺失状态与配对语义的归一化

## 版本控制 / 从仓库构建

本目录是独立的 Git 仓库（默认分支 `main`）。以下内容**故意不入库**：

| 路径 | 原因 |
| --- | --- |
| `Resources/ipa-signing/bundled/` | 本地内置签名凭据，绝不提交或外发 |
| `dist/`、`*.dmg`、`*.zip` | 打包产物，可由 `./build.sh` 复现 |
| `.build/` | SwiftPM 构建缓存与 dSYM |
| `.backup-*/` | 历次改版前的本地源码快照 |

从仓库 clone 后首次构建：

```bash
mkdir -p "Resources/ipa-signing/bundled"
# 可选：把自己的 cert.p12 + profile.mobileprovision 放进去
./build.sh
```

不放证书也能构建，App 会正常启动，只是没有内置默认证书，需要在界面里导入。公开的 CA 证书 `Resources/ipa-signing/AppleWWDRCAG3.cer` 已入库。

`docs/IPA-Dispatch-UI预览.html` 是 UI 预览的唯一版本控制源；会话工作区的同名文件是指向它的软链接，改一处即可。

> 项目位于 `~/Documents`，可能受 iCloud 同步影响。若 `.git` 出现同步冲突，建议把仓库移到非 iCloud 目录，或对该目录关闭 iCloud 同步。
