import SwiftUI
import UniformTypeIdentifiers

struct CertificateManagerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var deleteTarget: CertificateRecord?

    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("cert.manage"))
                        .font(.display(30))
                        .foregroundStyle(p.ink)
                    Text(model.t("cert.manageHelp"))
                        .font(.body(11.5))
                        .foregroundStyle(p.inkSoft)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)

            if model.certificates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(p.inkFaint)
                    Text(model.t("cert.none"))
                        .font(.body(13))
                        .foregroundStyle(p.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.certificates) { cert in
                            CertificateRow(cert: cert) {
                                model.selectCertificate(cert.id)
                                dismiss()
                            } onDelete: {
                                deleteTarget = cert
                            }
                            .environmentObject(model)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        model.openImportCertificate()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text(model.t("cert.import"))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 14)
        }
        .padding(26)
        .frame(width: 660, height: 580)
        .background(p.paper)
        .confirmationDialog(
            model.t("cert.delete.confirm"),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = deleteTarget {
                Button(model.t("common.delete"), role: .destructive) {
                    model.deleteCertificate(target)
                    deleteTarget = nil
                }
                Button(model.t("cancel"), role: .cancel) { deleteTarget = nil }
            }
        }
    }
}

private struct CertificateRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let cert: CertificateRecord
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var p: Palette { Palette(scheme: scheme) }
    private var selected: Bool { cert.id == model.selectedCertificateID }
    private var compatible: Bool {
        guard let device = model.selectedDevice else { return true }
        return cert.supports(device.udid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cert.valid ? p.verifiedSoft : p.signalSoft)
                    Image(systemName: cert.valid ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(cert.valid ? p.verified : p.danger)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(cert.isBuiltIn ? model.t("cert.builtIn") : cert.displayName)
                            .font(.body(14, weight: .semibold))
                            .foregroundStyle(p.ink)
                        if cert.isBuiltIn {
                            Text(model.t("cert.builtIn"))
                                .font(.data(7.5))
                                .foregroundStyle(p.inkFaint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(p.line))
                                .hidden()
                        }
                    }
                    HStack(spacing: 6) {
                        Text(cert.teamID)
                            .font(.data(9))
                            .foregroundStyle(p.inkSoft)
                        Text("·").foregroundStyle(p.inkFaint)
                        Text(cert.valid ? model.t("cert.validTo", cert.expiryLabel) : model.t("expired"))
                            .font(.body(10))
                            .foregroundStyle(cert.valid ? p.verified : p.danger)
                        if !compatible {
                            Text("·").foregroundStyle(p.inkFaint)
                            Text(model.t("device.incompatible"))
                                .font(.body(10))
                                .foregroundStyle(p.danger)
                        }
                    }
                    Text(cert.appID)
                        .font(.data(8.5))
                        .foregroundStyle(p.inkFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if selected {
                    Text(model.t("cert.selected"))
                        .font(.data(8, weight: .semibold))
                        .foregroundStyle(p.verified)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.verified.opacity(0.7)))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 9))
                    .foregroundStyle(p.inkFaint)
                if cert.allDevices {
                    Text(model.t("cert.allDevices"))
                        .font(.body(10))
                        .foregroundStyle(p.inkSoft)
                } else if cert.provisionedDevices.isEmpty {
                    Text(model.t("cert.noDevices"))
                        .font(.body(10))
                        .foregroundStyle(p.inkFaint)
                } else {
                    ForEach(cert.provisionedDevices.prefix(3), id: \.self) { udid in
                        Text(deviceLabel(for: udid))
                            .font(.data(8))
                            .foregroundStyle(p.inkSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(p.paperDeep))
                    }
                    if cert.provisionedDevices.count > 3 {
                        Text("+\(cert.provisionedDevices.count - 3)")
                            .font(.data(8))
                            .foregroundStyle(p.inkFaint)
                    }
                }
                Spacer()
                Button(model.t("cert.choose")) { onSelect() }
                    .buttonStyle(SecondaryButtonStyle())
                if !cert.isBuiltIn {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(p.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .help(model.t("common.delete"))
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(p.line.opacity(0.7)).frame(height: 1)
        }
    }

    private func deviceLabel(for udid: String) -> String {
        if let device = model.devices.first(where: { $0.udid == udid }) {
            return device.name
        }
        return String(udid.suffix(6))
    }
}

struct ImportCertificateSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var displayName = ""
    @State private var password = ""
    @State private var showP12Picker = false
    @State private var showProfilePicker = false
    @State private var localError = ""
    @State private var profileInfo: ProfileInfo?

    private var p: Palette { Palette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("cert.import.title"))
                        .font(.display(28))
                        .foregroundStyle(p.ink)
                    Text(model.t("cert.import.desc"))
                        .font(.body(11))
                        .foregroundStyle(p.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)

            VStack(spacing: 9) {
                fileRow(
                    title: model.t("cert.p12"),
                    url: p12URL,
                    choose: model.t("cert.import.chooseP12")
                ) { showP12Picker = true }
                fileRow(
                    title: model.t("cert.profile"),
                    url: profileURL,
                    choose: model.t("cert.import.chooseProfile")
                ) { showProfilePicker = true }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("cert.name"))
                    .font(.body(10.5, weight: .medium))
                    .foregroundStyle(p.inkSoft)
                TextField(model.t("cert.namePlaceholder"), text: $displayName)
                    .textFieldStyle(.plain)
                    .font(.body(13))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
            }
            .padding(.top, 13)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("password.label"))
                    .font(.body(10.5, weight: .medium))
                    .foregroundStyle(p.inkSoft)
                SecureField(model.t("password.placeholder"), text: $password)
                    .textFieldStyle(.plain)
                    .font(.body(13))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
            }
            .padding(.top, 12)

            if let profileInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profileInfo.name)
                        .font(.body(11, weight: .medium))
                        .foregroundStyle(p.ink)
                    Text(model.t("cert.import.devices", String(profileInfo.allDevices ? 0 : profileInfo.devices.count)))
                        .font(.body(10))
                        .foregroundStyle(p.inkSoft)
                }
                .padding(.top, 10)
            }

            if !localError.isEmpty || model.importError != nil {
                Text(localError.isEmpty ? model.importError! : localError)
                    .font(.body(10.5))
                    .foregroundStyle(p.danger)
                    .padding(.top, 9)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.isImportingCertificate {
                    ProgressView().controlSize(.small)
                    Text(model.t("cert.import.validating"))
                        .font(.body(10.5))
                        .foregroundStyle(p.inkSoft)
                }
                Spacer()
                Button(model.t("cancel")) { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(model.t("cert.import.button")) { submit() }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                    .disabled(!canSubmit || model.isImportingCertificate)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 520)
        .background(p.paper)
        .fileImporter(isPresented: $showP12Picker, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                p12URL = url
                localError = ""
            }
        }
        .fileImporter(isPresented: $showProfilePicker, allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                profileURL = url
                localError = ""
                profileInfo = try? CertificateStore.parseProfile(url)
            }
        }
    }

    private var canSubmit: Bool {
        p12URL != nil && profileURL != nil && !password.isEmpty
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(p.paperRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(p.line, lineWidth: 1)
            )
    }

    private func fileRow(title: String, url: URL?, choose: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 12))
                .foregroundStyle(url == nil ? p.inkFaint : p.verified)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body(10.5, weight: .medium))
                    .foregroundStyle(p.inkSoft)
                Text(url?.lastPathComponent ?? model.t("cert.import.noFile"))
                    .font(.data(9))
                    .foregroundStyle(url == nil ? p.inkFaint : p.ink)
                    .lineLimit(1)
            }
            Spacer()
            Button(choose, action: action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(fieldBackground)
    }

    private func submit() {
        guard let p12URL, let profileURL else {
            localError = model.t("cert.import.required")
            return
        }
        guard !password.isEmpty else {
            localError = model.t("error.password")
            return
        }
        localError = ""
        Task {
            await model.importCertificate(p12: p12URL, profile: profileURL, name: displayName, password: password)
        }
    }
}
