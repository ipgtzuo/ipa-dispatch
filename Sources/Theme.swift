import SwiftUI

struct Palette {
    let scheme: ColorScheme

    var paper: Color {
        scheme == .dark ? Color(red: 0.078, green: 0.086, blue: 0.074)
                        : Color(red: 0.941, green: 0.925, blue: 0.890)
    }
    var paperRaised: Color {
        scheme == .dark ? Color(red: 0.105, green: 0.115, blue: 0.099)
                        : Color(red: 0.976, green: 0.965, blue: 0.933)
    }
    var paperDeep: Color {
        scheme == .dark ? Color(red: 0.060, green: 0.067, blue: 0.058)
                        : Color(red: 0.905, green: 0.886, blue: 0.846)
    }
    var ink: Color {
        scheme == .dark ? Color(red: 0.925, green: 0.910, blue: 0.868)
                        : Color(red: 0.105, green: 0.125, blue: 0.108)
    }
    var inkSoft: Color {
        scheme == .dark ? Color(red: 0.660, green: 0.675, blue: 0.635)
                        : Color(red: 0.405, green: 0.415, blue: 0.380)
    }
    var inkFaint: Color {
        scheme == .dark ? Color(red: 0.470, green: 0.485, blue: 0.450)
                        : Color(red: 0.560, green: 0.555, blue: 0.515)
    }
    var line: Color {
        scheme == .dark ? Color(red: 0.245, green: 0.260, blue: 0.230)
                        : Color(red: 0.825, green: 0.802, blue: 0.748)
    }
    /// 卡片底色：比 paperRaised 再抬一档，让分组有可辨识的层级
    var card: Color {
        scheme == .dark ? Color(red: 0.130, green: 0.142, blue: 0.122)
                        : Color(red: 0.992, green: 0.982, blue: 0.958)
    }
    var signal: Color {
        scheme == .dark ? Color(red: 0.945, green: 0.400, blue: 0.220)
                        : Color(red: 0.862, green: 0.300, blue: 0.145)
    }
    var signalSoft: Color { signal.opacity(scheme == .dark ? 0.16 : 0.10) }
    var verified: Color {
        scheme == .dark ? Color(red: 0.470, green: 0.775, blue: 0.665)
                        : Color(red: 0.145, green: 0.405, blue: 0.330)
    }
    var verifiedSoft: Color { verified.opacity(scheme == .dark ? 0.15 : 0.09) }
    var danger: Color {
        scheme == .dark ? Color(red: 0.960, green: 0.430, blue: 0.370)
                        : Color(red: 0.675, green: 0.190, blue: 0.135)
    }
    var console: Color {
        scheme == .dark ? Color(red: 0.045, green: 0.050, blue: 0.043)
                        : Color(red: 0.085, green: 0.098, blue: 0.083)
    }
    var consoleText: Color { Color(red: 0.800, green: 0.820, blue: 0.770) }
    var shadow: Color { Color.black.opacity(scheme == .dark ? 0.40 : 0.10) }
}

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func data(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(Palette(scheme: scheme).line)
            .frame(height: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        let p = Palette(scheme: scheme)
        configuration.label
            .font(.body(13, weight: .semibold))
            .foregroundStyle(enabled ? p.chalkOnSignal : p.inkFaint)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(enabled ? p.signal : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(enabled ? Color.clear : p.line, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let p = Palette(scheme: scheme)
        configuration.label
            .font(.body(12.5, weight: .medium))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(p.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.64 : 1)
    }
}

extension Palette {
    var chalkOnSignal: Color { Color(red: 1.0, green: 0.965, blue: 0.915) }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // 只把 titlebar 设透明还不够：内容区仍会避开系统 titlebar，交通灯浮在
            // 上面一层、自定义顶栏落在下面一层，logo 与窗口控制按钮会错开约 28px。
            // 加 fullSizeContentView 让内容铺满整个窗口，交通灯与顶栏同处一排。
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
