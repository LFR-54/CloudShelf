import SwiftUI
import UniformTypeIdentifiers

/// The user's own Google key for a drive. Google then gives the drive its own quota instead of the one every
/// rclone user shares. A token only works with the key that obtained it, so a change signs in again.
struct GoogleKeyDialog: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    let drive: Drive
    @State private var client = OAuthClient()
    @State private var stored: OAuthClient?
    @State private var error: String?
    @State private var signIn: Task<Void, Never>?

    var body: some View {
        ModalSurface(width: 580) {
            VStack(alignment: .leading, spacing: 0) {
                ModalHead(title: "Clé Google de « \(drive.name) »",
                          subtitle: "Avec votre propre clé, Google accorde à ce lecteur son propre quota au lieu de celui que se partagent tous les utilisateurs de rclone.",
                          showsLogo: false, close: close)
                VStack(alignment: .leading, spacing: 0) {
                    GoogleKeyFields(client: $client, labelWidth: 96, invalid: error != nil) { error = $0 }
                    if let error {
                        FieldError(message: error)
                            .padding(.leading, 108)
                    }
                }
                .padding(16)
                .card()
                .padding(.horizontal, 22)
                Text("Votre navigateur s'ouvre pour autoriser CloudShelf avec cette clé. Un lecteur monté est ensuite remonté.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                footer
            }
        }
        .task {
            stored = await store.storedClient(drive)
            if let stored { client = stored }
        }
        .onDisappear { signIn?.cancel() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if stored != nil {
                Button("Revenir à la clé partagée") { connect(nil) }
                    .buttonStyle(PushButtonStyle.large)
                    .disabled(signIn != nil)
            }
            Spacer(minLength: 10)
            if signIn != nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("En attente du navigateur…")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            }
            Button("Annuler", action: close)
                .buttonStyle(PushButtonStyle.large)
            Button("Se connecter") { connect(client) }
                .buttonStyle(PushButtonStyle.largePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(signIn != nil)
        }
        .padding(.top, 16)
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }

    private func close() {
        signIn?.cancel()
        app.overlay = nil
    }

    /// Signs in with the key, or rclone's shared one when nil, and keeps the dialog open with the reason if it fails.
    private func connect(_ key: OAuthClient?) {
        if let message = key?.googleError {
            error = message
            return
        }
        error = nil
        let key = key?.trimmed
        signIn = Task {
            do {
                let account = try await store.setClient(drive, key)
                app.overlay = nil
                app.show(key == nil ? "Clé partagée de rclone rétablie pour \(account)" : "Clé Google enregistrée pour \(account)")
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            signIn = nil
        }
    }
}

/// Client ID and secret, typed or read from the JSON file Google Cloud offers when the client is created.
struct GoogleKeyFields: View {
    @Binding var client: OAuthClient
    let labelWidth: CGFloat
    var invalid = false
    let onError: (String?) -> Void

    static let guide = URL(string: "https://rclone.org/drive/#making-your-own-client-id")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("ID client") {
                FieldBox(text: $client.id, placeholder: "…apps.googleusercontent.com", invalid: invalid)
                    .accessibilityLabel("ID client")
            }
            row("Code secret") {
                FieldBox(text: $client.secret, placeholder: "GOCSPX-…", secure: true, invalid: invalid)
                    .accessibilityLabel("Code secret")
            }
            HStack(spacing: 14) {
                Button("Importer le fichier JSON…", action: importFile)
                    .buttonStyle(PushButtonStyle())
                Link("Créer une clé", destination: Self.guide)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.leading, labelWidth + 12)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: labelWidth, alignment: .leading)
            content()
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Importer"
        panel.message = "Choisissez le fichier JSON téléchargé à la création du client dans Google Cloud."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            client = try OAuthClient(googleFile: url)
            onError(nil)
        } catch {
            onError(error.localizedDescription)
        }
    }
}
