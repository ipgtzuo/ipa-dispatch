import SwiftUI
import AppKit

/// 窗口右上角的真实应用图标。build.sh 会把 Resources/AppIcon.icns 复制进
/// AppName.app/Contents/Resources/；源码直接运行或资源缺失时回退到矢量 BrandMark。
/// 刻意做成「无框水印」：它是纯展示，不该和左边两个可点击的带框按钮长得一样。
struct AppLogoMark: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 34
    private var p: Palette { Palette(scheme: scheme) }

    private static let icon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let icon = Self.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    // 只留一圈几乎看不见的边界，避免深色图标糊进深色顶栏；不加阴影。
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(p.line.opacity(0.5), lineWidth: 0.5)
                    )
            } else {
                BrandMark()
            }
        }
        .accessibilityLabel("IPA Dispatch")
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(p.signal)
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(p.chalkOnSignal)
        }
        .frame(width: 29, height: 29)
        .shadow(color: p.shadow, radius: 5, x: 0, y: 2)
    }
}

struct StatusChip: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let title: String
    let detail: String
    let active: Bool

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? p.verified : p.inkFaint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body(11.5, weight: .medium))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.data(8.5))
                    .foregroundStyle(active ? p.verified : p.inkFaint)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(p.inkFaint)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(p.paperRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(p.line, lineWidth: 1)
                )
        )
        .help(detail)
    }
}

struct StatusStamp: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let status: InstallStatus

    var body: some View {
        let p = Palette(scheme: scheme)
        let color: Color = {
            switch status {
            case .done: return p.verified
            case .failed: return p.danger
            case .running: return p.signal
            case .reading, .queued: return p.inkFaint
            }
        }()
        Text(model.t("stamp.\(status.rawValue)"))
            .font(.data(8.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color.opacity(0.75), lineWidth: 1)
            )
            .rotationEffect(.degrees(-2))
    }
}

struct AppTile: View {
    @Environment(\.colorScheme) private var scheme
    let initial: String
    let index: Int

    var body: some View {
        let p = Palette(scheme: scheme)
        let tint = index.isMultiple(of: 3) ? p.signal : (index.isMultiple(of: 2) ? p.verified : p.inkSoft)
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(p.paperDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(p.line, lineWidth: 1)
                )
            Text(initial)
                .font(.display(19))
                .foregroundStyle(p.ink)
            Rectangle()
                .fill(tint)
                .frame(width: 4, height: 18)
                .offset(x: -17)
        }
        .frame(width: 42, height: 42)
    }
}

struct InlineLogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let entries: [LogEntry]
    @State private var copied = false
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(p.signal).frame(width: 5, height: 5)
                Text(model.t("runLog"))
                    .font(.data(9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(p.consoleText)
                Text(model.t("lines", String(entries.count)))
                    .font(.data(8.5))
                    .foregroundStyle(p.consoleText.opacity(0.45))
                Spacer()
                Button {
                    let text = entries.map(\.text).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(model.t(copied ? "copied" : "copy"))
                    }
                    .font(.data(8.5))
                    .foregroundStyle(copied ? p.verified : p.consoleText.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help(model.t("copy"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1.5) {
                        ForEach(entries) { entry in
                            Text(entry.text)
                                .font(.data(9.2))
                                .lineSpacing(1.2)
                                .foregroundStyle(entry.isError ? Color(red: 0.95, green: 0.48, blue: 0.37) : p.consoleText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 170)
                .scrollIndicators(.visible)
                .onChange(of: entries.count) { _, _ in
                    guard let last = entries.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(p.console)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(p.consoleText.opacity(0.12), lineWidth: 1)
        )
    }
}

struct ManifestRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let item: IPAItem
    let index: Int
    @State private var logOpen = false

    private var itemLogs: [LogEntry] { model.itemLogs[item.id] ?? [] }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Text(String(format: "%02d", index + 1))
                    .font(.data(9))
                    .foregroundStyle(p.inkFaint)
                    .frame(width: 22, alignment: .leading)

                AppTile(initial: item.initial, index: index)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.body(14, weight: .semibold))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(item.bundleID.isEmpty ? model.t("readingBundle") : item.bundleID)
                            .font(.data(9.5))
                            .foregroundStyle(p.inkSoft)
                            .lineLimit(1)
                        Text("·").foregroundStyle(p.inkFaint)
                        Text(item.version.isEmpty ? "—" : "v\(item.version)")
                            .font(.data(9.5))
                            .foregroundStyle(p.inkFaint)
                        Text("·").foregroundStyle(p.inkFaint)
                        Text(item.sizeLabel)
                            .font(.data(9.5))
                            .foregroundStyle(p.inkFaint)
                    }
                }

                Spacer(minLength: 12)

                if item.status == .reading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }
                StatusStamp(status: item.status)

                if !itemLogs.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { logOpen.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                            Text(model.t("log"))
                            Text(String(itemLogs.count))
                                .font(.data(8))
                                .foregroundStyle(p.inkFaint)
                            Image(systemName: logOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.data(9))
                        .foregroundStyle(p.inkSoft)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(p.card)
                                .overlay(Capsule().stroke(p.line, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(model.t("log"))
                }

                if !model.isInstalling {
                    Button {
                        model.remove(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(p.inkFaint)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(model.t("remove"))
                }
            }
            .padding(.vertical, 14)

            if let message = item.message {
                HStack(spacing: 6) {
                    Image(systemName: item.status == .failed ? "exclamationmark.triangle" : "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                    Text(message)
                        .font(.body(10.5))
                        .lineLimit(2)
                }
                .foregroundStyle(item.status == .failed ? p.danger : p.inkSoft)
                .padding(.leading, 77)
                .padding(.bottom, 10)
            }

            if logOpen && !itemLogs.isEmpty {
                InlineLogView(entries: itemLogs)
                    .padding(.leading, 77)
                    .padding(.trailing, 2)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: item.status) { _, new in
            if new == .failed { logOpen = true }
        }
        .padding(.horizontal, 2)
        .background(
            item.status == .running ? p.signalSoft : (item.status == .failed ? p.danger.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(p.line.opacity(0.65)).frame(height: 1)
        }
    }
}

struct AddRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        Button {
            model.chooseFiles()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.t("addMore"))
                    .font(.body(11.5, weight: .medium))
                Spacer()
                Button {
                    model.showURLDownload = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                        Text(model.t("url.import"))
                    }
                    .font(.body(10.5))
                    .foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain)
                .disabled(model.isInstalling)
                Text(model.t("dropHint"))
                    .font(.body(10.5))
                    .foregroundStyle(p.inkFaint)
            }
            .foregroundStyle(p.inkSoft)
            .padding(.vertical, 13)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(model.isInstalling)
    }
}

private struct DropActionButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let p = Palette(scheme: scheme)
        configuration.label
            .font(.body(12.5, weight: .semibold))
            .foregroundStyle(primary ? p.chalkOnSignal : p.ink)
            .frame(width: 236, height: 24)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary ? p.signal : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(primary ? Color.clear : p.line, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DropZone: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(spacing: 16) {
            Spacer(minLength: 4)
            PackageGlyph()
            VStack(spacing: 7) {
                Text(model.t("drop.title"))
                    .font(.display(23))
                    .foregroundStyle(p.ink)
                Text(model.t("drop.subtitle"))
                    .font(.body(12))
                    .foregroundStyle(p.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 380)
            }
            Button {
                model.chooseFiles()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    Text(model.t("choose"))
                }
            }
            .buttonStyle(DropActionButtonStyle(primary: true))
            Button {
                model.showURLDownload = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                    Text(model.t("url.import"))
                }
            }
            .buttonStyle(DropActionButtonStyle(primary: false))
            Text(model.t("drop.formats"))
                .font(.data(9.5))
                .foregroundStyle(p.inkFaint)
                .padding(.top, 1)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.isDropTargeted ? p.signalSoft : p.paperRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(p.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(model.isDropTargeted ? p.signal : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: model.chooseFiles)
        .animation(.easeOut(duration: 0.18), value: model.isDropTargeted)
    }
}

struct PackageGlyph: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(p.line, lineWidth: 1)
                )
                .frame(width: 56, height: 68)
                .rotationEffect(.degrees(-7))
            VStack(spacing: 0) {
                Rectangle().fill(p.signal).frame(width: 56, height: 10)
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(p.ink)
                Spacer()
            }
            .frame(width: 56, height: 68)
            .rotationEffect(.degrees(-7))
        }
        .frame(width: 82, height: 82)
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let text: String
    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.danger)
                .padding(.top, 1)
            Text(text)
                .font(.body(11.5))
                .foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                model.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(p.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(p.signalSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(p.signal.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

/// 状态胶囊：带色点与浅底，不再做成旋转的「印章」，避免被误认成可点按钮。
/// 状态 + 签名方式合并成一枚胶囊。原先「本机签名」被 Spacer 顶到右栏底部，
/// 与「本次」卡片之间留一块空白、自己又孤零零一行，现在并入状态本身。
struct StampView: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let color: Color
    let note: String

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.data(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(color)
            Rectangle()
                .fill(p.line)
                .frame(width: 1, height: 11)
            Image(systemName: "lock.shield")
                .font(.system(size: 9, weight: .medium))
            Text(note)
                .font(.body(9.5))
        }
        .foregroundStyle(p.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        )
        .fixedSize()
        .help(note)
    }
}

struct ConsolePanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Binding var height: CGFloat
    @State private var dragStart: CGFloat?
    @State private var copied = false
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(p.signal).frame(width: 6, height: 6)
                Text(model.t("runLog"))
                    .font(.data(9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(p.consoleText)
                Text(model.t("lines", String(model.log.count)))
                    .font(.data(9))
                    .foregroundStyle(p.consoleText.opacity(0.45))
                Spacer()
                Button {
                    copyAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(model.t(copied ? "copied" : "copy"))
                    }
                    .font(.data(9))
                    .foregroundStyle(copied ? p.verified : p.consoleText.opacity(0.7))
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("copy"))
                Button {
                    model.log.removeAll()
                } label: {
                    Text(model.t("clear"))
                        .font(.data(9))
                        .foregroundStyle(p.consoleText.opacity(0.65))
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    model.showLog = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(p.consoleText.opacity(0.65))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("log.resize"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 7)
            .padding(.bottom, 5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log) { entry in
                            Text(entry.text)
                                .font(.data(10.1))
                                .lineSpacing(1.4)
                                .foregroundStyle(entry.isError ? Color(red: 0.95, green: 0.48, blue: 0.37) : p.consoleText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                }
                .onChange(of: model.log.count) { _, _ in
                    guard let last = model.log.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(p.console)
        .overlay(alignment: .top) {
            Capsule()
                .fill(p.consoleText.opacity(0.22))
                .frame(width: 38, height: 3)
                .padding(.top, 3)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStart == nil { dragStart = height }
                            let start = dragStart ?? height
                            height = min(440, max(150, start - value.translation.height))
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .help(model.t("log.resize"))
        }
    }

    private func copyAll() {
        let text = model.log.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            copied = false
        }
    }
}

struct URLImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var url = ""
    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandMark()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain)
                .disabled(model.isDownloadingURL)
            }
            .padding(.bottom, 22)

            Text(model.t("url.title"))
                .font(.display(27))
                .foregroundStyle(p.ink)
            Text(model.t("url.desc"))
                .font(.body(11.5))
                .foregroundStyle(p.inkSoft)
                .lineSpacing(2)
                .padding(.top, 7)
                .padding(.bottom, 18)

            TextField("https://example.com/app.ipa", text: $url)
                .textFieldStyle(.plain)
                .font(.body(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(p.paperRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(p.line, lineWidth: 1)
                        )
                )
                .disabled(model.isDownloadingURL)

            if let error = model.urlDownloadError {
                Text(error)
                    .font(.body(11))
                    .foregroundStyle(p.danger)
                    .padding(.top, 8)
            }

            if model.isDownloadingURL {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.t("url.downloading"))
                        .font(.body(11))
                        .foregroundStyle(p.inkSoft)
                }
                .padding(.top, 12)
            }

            HStack {
                Spacer()
                Button(model.t("cancel")) { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isDownloadingURL)
                Button(model.t("url.download")) { model.startURLDownload(url) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isDownloadingURL)
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 520)
        .background(p.paper)
        .interactiveDismissDisabled(model.isDownloadingURL)
    }
}

struct PasswordSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var password = ""
    @State private var error = ""

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandMark()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)

            Text(model.t("unlock.title"))
                .font(.display(29))
                .foregroundStyle(p.ink)
            Text(model.t("unlock.desc"))
                .font(.body(11.5))
                .foregroundStyle(p.inkSoft)
                .lineSpacing(2)
                .padding(.top, 7)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.t("password.label"))
                    .font(.body(10.5, weight: .medium))
                    .foregroundStyle(p.inkSoft)
                SecureField(model.t("password.placeholder"), text: $password)
                    .textFieldStyle(.plain)
                    .font(.body(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(p.paperRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(p.line, lineWidth: 1)
                            )
                    )
                    .onSubmit(submit)
            }

            if !error.isEmpty {
                Text(error)
                    .font(.body(11))
                    .foregroundStyle(p.danger)
                    .padding(.top, 8)
            }

            HStack {
                Spacer()
                Button(model.t("cancel")) { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(model.t(model.passwordPurpose == .signOnly ? "sign.only" : "install")) { submit() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 440)
        .background(p.paper)
        .interactiveDismissDisabled(model.isInstalling)
    }

    private func submit() {
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = model.t("error.password")
            return
        }
        dismiss()
        model.submitPassword(password)
    }
}
