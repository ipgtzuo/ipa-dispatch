import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        ZStack {
            p.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar()
                Hairline()
                HStack(spacing: 0) {
                    TargetSidebar()
                        .frame(width: 224)
                    Rectangle().fill(p.line).frame(width: 1)
                    ManifestPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(p.line).frame(width: 1)
                    DispatchSlip()
                        .frame(width: 312)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Hairline()
                BottomBar()
                    .frame(height: 66)
            }
            // 配合 WindowConfigurator 的 .fullSizeContentView：忽略系统 titlebar 留下的
            // 顶部安全区，让自定义顶栏从窗口最上沿开始，logo 与交通灯同处一排。
            .ignoresSafeArea(.all, edges: .top)
        }
        .frame(minWidth: 1040, minHeight: 660)
        .background(WindowConfigurator())
        .sheet(isPresented: $model.showPassword) {
            PasswordSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showCertificates) {
            CertificateManagerSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showImportCertificate) {
            ImportCertificateSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showURLDownload) {
            URLImportSheet().environmentObject(model)
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            // 品牌区：真实应用图标 + 标题，整体靠左；图标资源缺失时 AppLogoMark 会回退到矢量方块。
            AppLogoMark(size: 34)
                .padding(.trailing, 11)

            VStack(alignment: .leading, spacing: 1) {
                Text("IPA Dispatch")
                    .font(.display(17))
                    .foregroundStyle(p.ink)
                Text(model.t("app.subtitle"))
                    .font(.body(10))
                    .foregroundStyle(p.inkSoft)
            }

            Spacer(minLength: 20)

            // 语言切换与刷新组成一对完全一致的 28px 工具按钮，留在右上角。
            // 左侧品牌区只放图标与标题，不再塞工具控件。
            HStack(spacing: 8) {
                TopToolButton(helpText: model.t("language")) {
                    model.setLanguage(model.language == .zh ? .en : .zh)
                } label: {
                    Text(model.language.shortLabel)
                        .font(.data(10, weight: .semibold))
                }

                TopToolButton(helpText: model.t("refresh")) {
                    Task { await model.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }

            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 20)
        // 内容在 56px 顶栏里略微偏上：logo 比 12px 的交通灯大得多，
        // 纯居中会让它的中心比交通灯低约 12px，加底部留白后两者更接近同一排。
        .padding(.bottom, 12)
        .frame(height: 56)
    }
}

private struct TargetSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(model.t("sidebar.devices"))
                    .font(.body(11.5, weight: .semibold))
                    .foregroundStyle(p.ink)
                Spacer()
                Button {
                    Task { await model.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(p.inkFaint)
                }
                .buttonStyle(.plain)
                .help(model.t("device.refresh"))
            }
            .padding(.bottom, 8)

            if model.devices.isEmpty {
                Text(model.t("sidebar.noDevices"))
                    .font(.body(10.5))
                    .foregroundStyle(p.inkFaint)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.devices) { device in
                        DeviceSidebarRow(device: device)
                    }
                }
            }

            SlipRule().padding(.vertical, 10)

            HStack(spacing: 6) {
                Text(model.t("sidebar.certificates"))
                    .font(.body(11.5, weight: .semibold))
                    .foregroundStyle(p.ink)
                Spacer()
                Button {
                    model.openCertificateManager()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(p.inkFaint)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("sidebar.manage"))
            }
            .padding(.bottom, 7)

            if model.certificates.isEmpty {
                Text(model.t("sidebar.noCertificates"))
                    .font(.body(10.5))
                    .foregroundStyle(p.inkFaint)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.orderedCertificates) { cert in
                            CertificateSidebarRow(cert: cert)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // 按实际行数定高：ScrollView 默认会尽量撑满可用高度，只给 maxHeight
                // 时，哪怕只有 1 个证书也会占满 132px，在「证书」和检查卡片间留空白。
                // 超过 3 行封顶并可滚动。
                .frame(height: min(CGFloat(model.certificates.count), CGFloat(3)) * 41)
            }

            // 侧栏内容整体顶部成组；内容不足时留白自然落在底部。
            ReadinessCard()
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(p.paperDeep)
    }
}

/// 把「为什么还不能安装」直接摆在侧栏，而不是让用户去猜底部按钮为何是灰的。
private struct ReadinessCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    private var checks: [(String, Bool)] {
        [
            (model.t("check.device"), model.selectedDevice?.connected ?? false),
            (model.t("check.cert"), model.selectedCertificate?.valid ?? false),
            (model.t("check.packages"),
             !model.items.isEmpty && !model.isReading && !model.items.contains { $0.bundleID.isEmpty })
        ]
    }

    private var passedCount: Int { checks.filter { $0.1 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(model.t("check.title"))
                    .font(.body(11, weight: .semibold))
                    .foregroundStyle(p.ink)
                Spacer()
                Text("\(passedCount)/\(checks.count)")
                    .font(.data(9.5, weight: .semibold))
                    .foregroundStyle(passedCount == checks.count ? p.verified : p.inkSoft)
            }

            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 7) {
                    Image(systemName: check.1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(check.1 ? p.verified : p.inkFaint)
                    Text(check.0)
                        .font(.body(10.5))
                        .foregroundStyle(check.1 ? p.inkSoft : p.ink)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                }
            }

            Text(model.canInstall ? model.t("check.allReady") : model.t("check.hint"))
                .font(.body(9.5))
                .foregroundStyle(model.canInstall ? p.verified : p.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(p.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(p.line, lineWidth: 1)
                )
        )
    }
}

private struct DeviceSidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let device: DeviceRecord
    private var p: Palette { Palette(scheme: scheme) }
    private var selected: Bool { device.udid == model.selectedDeviceID }

    var body: some View {
        Button {
            model.selectDevice(device.udid)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(device.connected ? p.verified : p.inkFaint)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.body(12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? p.ink : p.inkSoft)
                        .lineLimit(1)
                    Text(device.connected ? model.t("device.connected") : model.t("device.notConnected"))
                        .font(.body(10))
                        .foregroundStyle(device.connected ? p.verified.opacity(0.8) : p.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(p.ink)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? p.paperRaised : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(p.signal)
                        .frame(width: 2, height: 18)
                }
            }
        }
        .buttonStyle(.plain)
        .help(device.udid)
    }
}

private struct CertificateSidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let cert: CertificateRecord
    private var p: Palette { Palette(scheme: scheme) }
    private var selected: Bool { cert.id == model.selectedCertificateID }
    private var compatible: Bool {
        guard let device = model.selectedDevice else { return true }
        return cert.supports(device.udid)
    }

    var body: some View {
        Button {
            model.selectCertificate(cert.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: cert.valid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(cert.valid ? p.verified : p.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cert.isBuiltIn ? model.t("cert.builtIn") : cert.displayName)
                        .font(.body(11.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? p.ink : p.inkSoft)
                        .lineLimit(1)
                    Text(cert.expiryLabel)
                        .font(.data(9.5))
                        .foregroundStyle(p.inkFaint)
                }
                Spacer(minLength: 2)
                if !compatible {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(p.danger.opacity(0.8))
                } else if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(p.ink)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? p.paperRaised : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(p.signal)
                        .frame(width: 2, height: 18)
                }
            }
            .opacity(compatible ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!compatible)
        .help(compatible ? cert.teamID : model.t("device.incompatible"))
    }
}

private struct DeviceMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }
    private var device: DeviceRecord? { model.selectedDevice }

    var body: some View {
        Menu {
            if model.devices.isEmpty {
                Text(model.t("device.noneAvailable"))
            } else {
                ForEach(model.devices) { item in
                    Button {
                        model.selectDevice(item.udid)
                    } label: {
                        HStack {
                            Image(systemName: item.udid == model.selectedDeviceID ? "checkmark" : (item.connected ? "iphone" : "iphone.slash"))
                            Text(item.name)
                            Text(item.connected
                                 ? (item.state.lowercased().contains("paired") ? model.t("device.pairedLocal") : model.t("device.connected"))
                                 : model.t("device.notConnected"))
                        }
                    }
                }
            }
            Divider()
            Button(model.t("device.refresh")) {
                Task { await model.refreshDevices() }
            }
        } label: {
            StatusChip(
                icon: "iphone",
                title: device?.name ?? model.t("device.none"),
                detail: model.deviceStateLabel,
                active: device?.connected ?? false
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: 205, alignment: .leading)
    }
}

private struct CertificateMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }
    private var cert: CertificateRecord? { model.selectedCertificate }

    var body: some View {
        Menu {
            if model.certificates.isEmpty {
                Text(model.t("cert.none"))
            } else {
                ForEach(model.certificates) { item in
                    let compatible = model.selectedDevice.map { item.supports($0.udid) } ?? true
                    Button {
                        model.selectCertificate(item.id)
                    } label: {
                        HStack {
                            Image(systemName: item.id == model.selectedCertificateID ? "checkmark" : (compatible ? "checkmark.seal" : "xmark.seal"))
                            Text(item.isBuiltIn ? model.t("cert.builtIn") : item.displayName)
                            Text(item.expiryLabel)
                        }
                    }
                    .disabled(!compatible)
                }
            }
            Divider()
            Button(model.t("cert.manage")) { model.openCertificateManager() }
            Button(model.t("cert.import")) { model.openImportCertificate() }
        } label: {
            StatusChip(
                icon: "checkmark.seal",
                title: cert.map { $0.isBuiltIn ? model.t("cert.builtIn") : $0.displayName } ?? model.t("cert.none"),
                detail: cert.map { $0.valid ? model.t("cert.validTo", $0.expiryLabel) : model.t("cert.unavailable") } ?? model.t("cert.unavailable"),
                active: cert?.valid ?? false
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: 235, alignment: .leading)
    }
}

/// 顶栏工具按钮：语言切换与刷新共用同一套尺寸、底色和描边，保证成对时外观完全一致。
/// 语言只有中/英两种，点一下直接切换，不再用下拉菜单（Menu 的 borderlessButton
/// 样式会吃掉自定义背景，导致两个按钮一个有框、一个没框）。
private struct TopToolButton<Label: View>: View {
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }
    let helpText: String
    let action: () -> Void
    private let content: () -> Label

    init(helpText: String,
         action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.helpText = helpText
        self.action = action
        self.content = label
    }

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(p.inkSoft)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(p.paperRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(p.line, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

private struct ManifestPane: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    private var countLabel: String {
        if model.items.isEmpty { return model.t("packages.none") }
        if model.items.count == 1 { return model.t("packages.one") }
        return model.t("packages.n", String(model.items.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.t("manifest"))
                    .font(.display(28))
                    .foregroundStyle(p.ink)
                // 计数徽章贴在标题旁，不再和右栏「0 个 IPA」重复表达空状态
                Text(countLabel)
                    .font(.data(9.5))
                    .foregroundStyle(p.inkSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(p.card)
                            .overlay(Capsule().stroke(p.line, lineWidth: 1))
                    )
                Spacer()
                if !model.items.isEmpty {
                    Text(model.t("manifest.order"))
                        .font(.body(10.5))
                        .foregroundStyle(p.inkFaint)
                }
            }
            Text(model.t("manifest.subtitle"))
                .font(.body(12.5))
                .foregroundStyle(p.inkSoft)
                .padding(.top, 2)
                .padding(.bottom, 14)

            if let error = model.error {
                ErrorBanner(text: model.t(error))
                    .padding(.bottom, 14)
            }

            if model.items.isEmpty {
                // 空状态占满主区，避免下方出现整片无内容的留白
                DropZone()
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ManifestRow(item: item, index: index)
                        }
                        AddRow()
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { isTargeted in
            model.isDropTargeted = isTargeted
        }
    }
}

private struct DispatchSlip: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    private var device: DeviceRecord? { model.selectedDevice }
    private var cert: CertificateRecord? { model.selectedCertificate }

    private var stamp: (String, Color) {
        if model.isInstalling { return (model.t("stamp.signing"), p.signal) }
        if !model.items.isEmpty && model.items.allSatisfy({ $0.status == .done }) {
            return (model.t("stamp.dispatched"), p.verified)
        }
        if model.canInstall { return (model.t("stamp.ready"), p.verified) }
        return (model.t("stamp.waiting"), p.inkFaint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("dispatch.title"))
                        .font(.display(18))
                        .foregroundStyle(p.ink)
                    Text(model.t("dispatch.no", String(format: "%03d", model.items.count)))
                        .font(.data(9.5))
                        .foregroundStyle(p.inkFaint)
                }
                Spacer()
                // 状态与签名方式合并成一枚胶囊，底部不再留孤立的注脚
                StampView(label: stamp.0, color: stamp.1, note: model.t("localSigning"))
            }
            .padding(.bottom, 14)

            SlipSection(title: model.t("destination")) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(p.ink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device?.name ?? model.t("device.none"))
                            .font(.body(14, weight: .semibold))
                            .foregroundStyle(p.ink)
                        Text(device?.udid ?? "—")
                            .font(.data(10))
                            .foregroundStyle(p.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(device?.udid ?? "")
                        HStack(spacing: 5) {
                            Circle()
                                .fill(device?.connected == true ? p.verified : p.inkFaint)
                                .frame(width: 5, height: 5)
                            Text(model.deviceStateLabel)
                                .font(.body(10.5))
                                .foregroundStyle(device?.connected == true ? p.verified : p.inkSoft)
                        }
                    }
                }
            }

            SlipRule()

            SlipSection(title: model.t("signing")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(cert.map { $0.isBuiltIn ? model.t("cert.builtIn") : $0.displayName } ?? model.t("profile.none"))
                        .font(.body(12.5, weight: .medium))
                        .foregroundStyle(p.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(model.t("team"))
                            .font(.body(10))
                            .foregroundStyle(p.inkFaint)
                        Text(cert?.teamID.isEmpty == false ? cert!.teamID : "—")
                            .font(.data(10))
                            .foregroundStyle(p.inkSoft)
                    }
                    Text(cert?.appID.isEmpty == false ? cert!.appID : "—")
                        .font(.data(9.5))
                        .foregroundStyle(p.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cert?.appID ?? "")
                    HStack(spacing: 6) {
                        Text(cert?.valid == true ? model.t("validUntil") : model.t("expired"))
                            .font(.body(10))
                            .foregroundStyle(p.inkFaint)
                        Text(cert?.expiryLabel ?? "—")
                            .font(.data(10))
                            .foregroundStyle(cert?.valid == true ? p.verified : p.danger)
                    }
                    if let cert {
                        Text(cert.allDevices
                             ? model.t("cert.allDevices")
                             : (cert.provisionedDevices.count == 1
                                ? model.t("cert.deviceCount.one")
                                : model.t("cert.deviceCount", String(cert.provisionedDevices.count))))
                            .font(.body(10))
                            .foregroundStyle(p.inkFaint)
                    }
                }
            }

            SlipRule()

            SlipSection(title: model.t("thisRun")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(model.items.count)")
                            .font(.display(28))
                            .foregroundStyle(p.ink)
                        Text(model.items.count == 1 ? model.t("package.one") : model.t("package.many"))
                            .font(.body(11.5))
                            .foregroundStyle(p.inkSoft)
                        Spacer()
                        Text(model.batchSizeLabel)
                            .font(.data(10.5))
                            .foregroundStyle(p.inkSoft)
                    }
                    Rectangle().fill(p.line).frame(height: 1)
                    Text(model.t("conflictNote"))
                        .font(.body(10.5))
                        .foregroundStyle(p.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(p.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(p.line, lineWidth: 1)
                        )
                )
            }

        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.paperRaised)
    }
}

private struct SlipSection<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let content: Content
    private var p: Palette { Palette(scheme: scheme) }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(p.signal).frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.body(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(p.ink)
            }
            content
        }
        .padding(.vertical, 13)
    }
}

private struct SlipRule: View {
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }
    var body: some View {
        Rectangle().fill(p.line.opacity(0.8)).frame(height: 1)
    }
}

private struct BottomBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(scheme: scheme) }

    /// 显式告诉用户「还差什么」，而不是只给一个灰色按钮
    private var nextHint: String {
        if model.items.isEmpty { return model.t("next.addPackages") }
        if model.isReading { return model.t("status.reading") }
        if !(model.selectedDevice?.connected ?? false) { return model.t("next.connectDevice") }
        if !(model.selectedCertificate?.valid ?? false) { return model.t("next.selectCert") }
        if let device = model.selectedDevice, let cert = model.selectedCertificate,
           !cert.supports(device.udid) { return model.t("next.incompatible") }
        return model.t("next.addPackages")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isInstalling ? p.signal : (model.canInstall ? p.verified : p.inkFaint))
                        .frame(width: 6, height: 6)
                    Text(model.t(model.status))
                        .font(.body(11.5, weight: .medium))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    if !model.canInstall && !model.isInstalling {
                        Text("·").foregroundStyle(p.inkFaint)
                        Text(nextHint)
                            .font(.body(11))
                            .foregroundStyle(p.inkFaint)
                            .lineLimit(1)
                    }
                }
                if model.isInstalling || model.progress > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.line)
                            Capsule()
                                .fill(p.signal)
                                .frame(width: proxy.size.width * model.progress)
                        }
                    }
                    .frame(width: 250, height: 3)
                }
            }

            Spacer()

            Button {
                model.requestSignOnly()
            } label: {
                Label(model.t("sign.only"), systemImage: "signature")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!model.canSignOnly)
            .help(model.canSignOnly ? model.t("sign.only.help") : model.t("error.profile"))

            Button {
                model.chooseSignedIPAFiles()
            } label: {
                Label(model.t("install.signed"), systemImage: "square.and.arrow.down")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isInstalling || !(model.selectedDevice?.connected ?? false))
            .help(model.selectedDevice?.connected == true ? model.t("install.signed") : model.t("device.notConnected"))

            if !model.items.isEmpty && !model.isInstalling {
                Button(model.t("clear")) { model.clear() }
                    .buttonStyle(SecondaryButtonStyle())
            }

            Button {
                model.requestInstall()
            } label: {
                HStack(spacing: 8) {
                    if model.isInstalling {
                        ProgressView().controlSize(.small).tint(p.chalkOnSignal)
                    }
                    Text(model.installButtonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: model.canInstall || model.isInstalling))
            .disabled(!model.canInstall && !model.isInstalling)
            .help(!model.canInstall && !model.isInstalling ? nextHint : model.t("install"))
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(p.paperRaised)
    }
}
