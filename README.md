# IPA Dispatch

一个 macOS 桌面工具，用来给自己的或已获授权的 IPA 做本地签名、批量签名，并安装到已连接的 iPhone / iPad。

## 功能

- 拖入或多选 IPA，按列表顺序逐个处理
- 大文件/超大 IPA 采用流式检查与解压，不把整个文件读进内存；安装前检查可用磁盘空间
- 从 URL 下载 IPA 后直接加入清单
- 中英文界面切换
- 左侧设备/证书栏：设备顺序与证书顺序保持一致，整行可点击
- 多设备、多证书；证书按描述文件的 `ProvisionedDevices` 与设备自动匹配，不兼容的证书灰显
- 齿轮进入证书管理：导入 `.p12` + `.mobileprovision`，或删除已有证书
- 两种工作流：
  - **安装 IPA**：签名后直接安装到当前连接的设备
  - **仅签名**：只导出已签名 IPA，不要求连接设备；支持一次选择多个 IPA
- **安装已签名**：选择一个或多个已签名 IPA，安装到当前连接的设备
- 每个 IPA 都有可展开/折叠的独立日志，失败自动展开，支持一键复制
- 批量任务失败不会中断后续 IPA
- bundle ID 冲突时自动安装为 `.sideload1/2/...` 副本
- p12 密码只在本次运行的内存中使用，不写入磁盘

## 使用

1. 打开 `dist/IPA-Dispatch.dmg`，把 `IPA Dispatch.app` 拖到 Applications
2. 连接 iPhone/iPad，解锁并信任这台 Mac
3. 左侧设备栏选择目标设备
4. 点证书栏的齿轮，导入自己的 `.p12` + `.mobileprovision`，选择兼容证书
5. 拖入 IPA，或点「选择 IPA 文件」/「从 URL 下载」
6. 点「安装 IPA」；如果只需要签名，点「仅签名」并选择导出目录
7. 安装已签名 IPA 时，点「安装已签名」选择文件

### 仅签名 / 安装已签名

- **仅签名**：选择输出目录后，为清单中的每个 IPA 生成 `*-signed.ipa`；没有连接设备也可以操作
- **安装已签名**：要求当前设备已连接；可一次选择多个 `.ipa`，按顺序安装

### 导入证书

在证书管理页选择：

- `.p12` 证书文件
- 匹配的 `.mobileprovision`
- 显示名称
- p12 密码（只用于验证和本次安装）

导入时会检查密码/私钥、描述文件有效期、团队/App ID 和设备列表。证书文件复制到：

```text
~/Library/Application Support/IPA Dispatch/Certificates/
```

## 设备连接

App 通过 `xcrun devicectl` 读取设备。安装和「安装已签名」只对已连接设备开放；「仅签名」不要求设备在线。

如果 Finder 能看到设备但 App 显示未连接，先确认：

- 使用 USB 数据线，而不是只供电的线
- 设备已解锁，并点了「信任此电脑」
- 设备已开启开发者模式
- `xcrun devicectl device info details --device <UDID>` 显示 `Device State: connected`

Wi-Fi 连接可以用于识别设备，但大文件安装建议使用 USB。

## 构建

```bash
cd ipa-dispatch
./build.sh
```

要求：Xcode / Swift 6 toolchain、macOS 14+。构建脚本会在本地临时目录编译、ad-hoc 签名并生成：

```text
dist/IPA-Dispatch.dmg
dist/IPA-Dispatch.zip
```

### 运行测试

```bash
./run-tests.sh
```

只编译设备状态的纯逻辑层和测试，不需要连接设备。

## 签名凭据 / 隐私

- **本仓库不包含任何 `.p12`、`.mobileprovision`、设备 UDID 或证书团队信息**
- 需要签名时请放入自己的证书，或通过 App 的证书管理导入
- 本地证书目录被 `.gitignore` 排除；不要把 `Resources/ipa-signing/` 下的私钥提交或外发
- App 使用本地 ad-hoc 签名，未做 Apple 公证；Gatekeeper 拦截时右键 App → 打开
- 请只用于自己拥有或已获授权的 IPA

## 目录

```text
Sources/                 SwiftUI App
Resources/sign-ios-ipa.sh  签名/安装脚本
Tests/DeviceStateTests.swift
docs/IPA-Dispatch-UI预览.html
build.sh
run-tests.sh
```
