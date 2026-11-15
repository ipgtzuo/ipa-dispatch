import SwiftUI

@main
struct IPADispatchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("IPA Dispatch") {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.t("choose")) {
                    model.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Install") {
                Button(model.t("install")) {
                    model.requestInstall()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.canInstall)

                Divider()

                Button(model.t("device.refresh")) {
                    Task { await model.refreshDevices() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(model.t("cert.manage")) {
                    model.openCertificateManager()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(model.t("cert.import")) {
                    model.openImportCertificate()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button(model.language == .zh ? "English" : "中文") {
                    model.setLanguage(model.language == .zh ? .en : .zh)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
