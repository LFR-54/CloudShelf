import SwiftUI

/// Dims the window and shows the current dialog in the middle, as the mockup's scrim does.
struct DialogHost: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        if let overlay = app.overlay {
            GeometryReader { geometry in
                ZStack {
                    Theme.scrim
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    dialog(overlay)
                        .environment(\.dialogSpace, geometry.size)
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func dialog(_ overlay: AppState.Overlay) -> some View {
        switch overlay {
        case .alert(let alert):
            AlertDialog(alert: alert)
        case .about:
            AboutDialog()
        case .notes:
            NotesDialog()
        case .log(let id):
            if let drive = store.drive(id) { LogDialog(drive: drive) }
        case .options(let id):
            if let drive = store.drive(id) { OptionsDialog(drive: drive) }
        case .googleKey(let id):
            if let drive = store.drive(id) { GoogleKeyDialog(drive: drive) }
        case .add(let provider):
            ConnectionDialog(provider: Provider.named(provider), editing: nil)
        case .edit(let id):
            if let drive = store.drive(id) { ConnectionDialog(provider: drive.provider, editing: drive) }
        }
    }
}

/// Dialog surface: the window color, 20 pt corners and the mockup's shadow.
struct ModalSurface<Content: View>: View {
    @Environment(\.dialogSpace) private var space
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: min(width, space.width - 40))
            .background(Theme.window, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .hairlineBorder(RoundedRectangle(cornerRadius: 20, style: .continuous), .black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 35, y: 24)
    }
}

/// Close button, optional logo, title and subtitle.
struct ModalHead: View {
    let title: String
    let subtitle: String
    var showsLogo = true
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CloseButton(action: close)
                .padding(.trailing, 6)
            if showsLogo { AppLogo(size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .lineBox(19)
                Text(subtitle)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 20)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }
}

struct AlertDialog: View {
    @Environment(AppState.self) private var app
    let alert: AppState.Alert

    var body: some View {
        ModalSurface(width: 300) {
            VStack(spacing: 0) {
                AppLogo(size: 60)
                    .padding(.bottom, 12)
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                HStack(spacing: 8) {
                    Button("Annuler") { app.overlay = nil }
                        .buttonStyle(PushButtonStyle.pair())
                        .keyboardShortcut(.cancelAction)
                    Button(alert.confirm) {
                        app.overlay = nil
                        alert.action()
                    }
                    .buttonStyle(PushButtonStyle.pair(alert.destructive ? .danger : .primary))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }
}

struct AboutDialog: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        ModalSurface(width: 372) {
            VStack(spacing: 0) {
                AppLogo(size: 112, shadowRadius: 5, shadowY: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                Text("CloudShelf")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.26)
                Text("Version \(Preferences.appVersion) (\(Preferences.appBuild))")
                    .foregroundStyle(Theme.text2)
                    .monospacedDigit()
                    .padding(.top, 3)
                VStack(spacing: 0) {
                    ForEach(Array(info.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Hairline() }
                        HStack(spacing: 12) {
                            Text(item.label).foregroundStyle(Theme.text2)
                            Spacer(minLength: 0)
                            Text(item.value).fontWeight(.semibold)
                        }
                        .font(.system(size: 12.5))
                        .lineBox(12.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .card()
                .padding(.top, 18)
                .padding(.bottom, 14)
                Button("Notes de version") { app.overlay = .notes }
                    .buttonStyle(PushButtonStyle.pair())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(versionText, forType: .string)
                    app.show("Informations de version copiées")
                } label: {
                    Label("Copier les informations de version", systemImage: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .overlay(alignment: .topLeading) {
                CloseButton { app.overlay = nil }
                    .padding(14)
            }
        }
    }

    private var info: [(label: String, value: String)] {
        [("Moteur", "rclone \(store.engineRelease ?? "…")"),
         ("Montage", MacFUSE.version.map { "macFUSE \($0) · NFS intégré" } ?? "NFS intégré"),
         ("Système", "\(Self.system) · \(Self.architecture)"),
         ("Licence de rclone", "MIT")]
    }

    private var versionText: String {
        "CloudShelf \(Preferences.appVersion) (\(Preferences.appBuild))\nrclone \(store.engineVersion ?? "")\n"
            + (MacFUSE.version.map { "macFUSE \($0), NFS intégré" } ?? "NFS intégré") + "\n\(Self.system), \(Self.architecture)"
    }

    static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.minorVersion > 0 ? "macOS \(version.majorVersion).\(version.minorVersion)" : "macOS \(version.majorVersion)"
    }

    static var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }
}

/// The user's own rclone flags for a drive, added after the profile's.
struct OptionsDialog: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    let drive: Drive
    @State private var text = ""

    var body: some View {
        ModalSurface(width: 560) {
            VStack(alignment: .leading, spacing: 0) {
                ModalHead(title: "Options rclone de « \(drive.name) »",
                          subtitle: "Ajoutées à la commande de montage, après celles du profil.", showsLogo: false) { app.overlay = nil }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profil \(drive.settings.profile.rawValue)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                    Text(MountOptions.profileFlags(drive.settings).joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                    Text("Vos options")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .padding(.top, 8)
                    FieldBox(text: $text, placeholder: "--vfs-cache-max-age 2h --transfers 8", onSubmit: save)
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(16)
                .card()
                .padding(.horizontal, 22)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Annuler") { app.overlay = nil }
                        .buttonStyle(PushButtonStyle.large)
                    Button("Enregistrer", action: save)
                        .buttonStyle(PushButtonStyle.largePrimary)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 16)
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .onAppear { text = drive.settings.extraOptions }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespaces)
        app.overlay = nil
        guard value != drive.settings.extraOptions else { return }
        store.update(drive) { $0.extraOptions = value }
        guard store.appliesLater(drive) else { return app.show("Options enregistrées") }
        Task {
            await store.remount(drive)
            app.show("« \(drive.name) » remonté avec les nouvelles options")
        }
    }
}
