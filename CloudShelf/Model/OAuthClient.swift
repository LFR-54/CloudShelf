import Foundation

/// The user's own OAuth app key, stored by rclone as client_id and client_secret. Without it, rclone signs in
/// with its own key, which every rclone user shares and Google throttles when they are too many at once.
struct OAuthClient: Equatable, Sendable {
    var id = ""
    var secret = ""

    /// The key stored on a remote, or nil for rclone's shared one.
    init?(stored: [String: String]) {
        guard let id = stored["client_id"], !id.isEmpty else { return nil }
        self.id = id
        secret = stored["client_secret"] ?? ""
    }

    init(id: String = "", secret: String = "") {
        self.id = id
        self.secret = secret
    }

    var trimmed: OAuthClient {
        OAuthClient(id: id.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What is wrong with a Google key as typed, if anything.
    var googleError: String? {
        let key = trimmed
        if key.id.isEmpty { return "Saisissez l'ID client." }
        if !key.id.hasSuffix(".apps.googleusercontent.com") { return "L'ID client se termine par .apps.googleusercontent.com." }
        if key.secret.isEmpty { return "Saisissez le code secret." }
        return nil
    }

    /// The JSON file Google Cloud offers when the client is created.
    init(googleFile url: URL) throws {
        struct File: Decodable {
            struct Client: Decodable {
                let client_id: String
                let client_secret: String
            }
            let installed: Client?
            let web: Client?
        }
        guard let file = try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)), let client = file.installed ?? file.web else {
            throw RcloneError.command("Ce fichier n'est pas une clé OAuth de Google Cloud.")
        }
        self.init(id: client.client_id, secret: client.client_secret)
    }
}
