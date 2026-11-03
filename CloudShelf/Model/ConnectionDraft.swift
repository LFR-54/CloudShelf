import Foundation

/// The add and edit dialog's form, turned into rclone parameters.
struct ConnectionDraft: Equatable {
    enum Field: Hashable {
        case name, client, signIn, email, password, endpoint, bucket, accessKey, secretKey, address, encryptionPassword
    }

    var provider: Provider
    var name: String
    var token: String?
    var authorizedAccount: String?
    /// The user's own app key for a new OAuth drive; the token must come from it.
    var client: OAuthClient?
    var email = ""
    var password = ""
    var twoFactor = ""
    var endpoint = ""
    var bucket = ""
    var accessKey = ""
    var secretKey = ""
    var address = ""
    var port = ""
    var path = ""
    var user = ""
    var anonymous = false
    var profile = Profile.documents
    var method = MountMethod.nfs
    var timeout = "300"
    var mountAtLogin = true
    var readOnly = false
    var skipCertificateCheck = false
    var encrypt = false
    var encryptionPassword = ""

    init(provider: Provider, name: String) {
        self.provider = provider
        self.name = name
        port = provider.port.map(String.init) ?? ""
    }

    /// Prefills an edit from the drive and its stored, non-secret parameters.
    @MainActor
    init(drive: Drive, stored: [String: String]) {
        self.init(provider: drive.provider, name: drive.name)
        authorizedAccount = drive.record.account
        email = stored["user"] ?? stored["username"] ?? ""
        endpoint = stored["endpoint"] ?? ""
        accessKey = stored["access_key_id"] ?? ""
        bucket = drive.provider.kind == .s3 ? drive.record.path : ""
        path = drive.provider.kind == .server ? drive.record.path : ""
        user = stored["user"] ?? ""
        if let url = stored["url"] {
            address = url
        } else if let host = stored["host"] {
            address = host
            port = stored["port"] ?? port
        }
        anonymous = drive.provider.type == "ftp" && user == "anonymous"
        let settings = drive.settings
        profile = settings.profile
        method = settings.method
        timeout = "\(settings.timeout)"
        mountAtLogin = settings.mountAtLogin
        readOnly = settings.readOnly
        skipCertificateCheck = settings.skipCertificateCheck
    }

    /// rclone parameters; empty values are left out, so an edit keeps the stored secrets.
    var parameters: [String: String] {
        let values: [String: String]
        switch provider.kind {
        case .oauth:
            values = ["token": token ?? "", "client_id": client?.trimmed.id ?? "", "client_secret": client?.trimmed.secret ?? ""]
        case .login:
            values = provider.type == "mega"
                ? ["user": email, "pass": password, "2fa": twoFactor]
                : ["username": email, "password": password, "2fa": twoFactor]
        case .s3:
            values = ["provider": "Other", "env_auth": "false", "endpoint": endpoint, "access_key_id": accessKey, "secret_access_key": secretKey]
        case .server:
            switch provider.type {
            case "webdav":
                values = ["url": serverURL, "vendor": provider.vendor ?? "other", "user": user, "pass": password]
            case "ftp":
                values = ["host": host, "port": port, "user": anonymous ? "anonymous" : user, "pass": anonymous ? "anonymous" : password,
                          "explicit_tls": address.lowercased().hasPrefix("ftps://") ? "true" : ""]
            default:
                values = ["host": host, "port": port, "user": user, "pass": password]
            }
        }
        // Anonymous access sends no credentials, except FTP's conventional anonymous login above.
        let credentials: Set = anonymous && provider.type != "ftp" ? ["user", "pass"] : []
        return values.filter { !credentials.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The path inside the remote: the bucket, or the path typed for a server.
    var remotePath: String {
        switch provider.kind {
        case .s3: bucket.trimmingCharacters(in: .whitespaces)
        case .server: path.trimmingCharacters(in: .whitespaces)
        default: ""
        }
    }

    var accountLabel: String? {
        let value = switch provider.kind {
        case .oauth: authorizedAccount ?? ""
        case .login: email
        case .s3: bucket
        case .server: user.isEmpty || anonymous ? host : user
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var settings: DriveSettings {
        var settings = DriveSettings()
        settings.profile = profile
        settings.method = method
        settings.timeout = Int(timeout) ?? 300
        settings.mountAtLogin = mountAtLogin
        settings.readOnly = readOnly
        settings.skipCertificateCheck = skipCertificateCheck
        settings.cacheMaxGB = switch profile {
        case .streaming: 200
        case .documents: 20
        case .backup: 5
        }
        return settings
    }

    /// Missing fields, in the mockup's wording. An edit keeps the stored secrets and token.
    func errors(editing: Bool) -> [Field: String] {
        var errors: [Field: String] = [:]
        func require(_ value: String, _ field: Field, _ message: String) {
            if value.trimmingCharacters(in: .whitespaces).isEmpty { errors[field] = message }
        }
        switch provider.kind {
        case .oauth:
            if let error = client?.googleError { errors[.client] = error }
            if token == nil && !editing { errors[.signIn] = "Connectez-vous à \(provider.name) pour continuer." }
        case .login:
            require(email, .email, "Saisissez l'adresse e-mail.")
            if !editing { require(password, .password, "Saisissez le mot de passe.") }
        case .s3:
            require(endpoint, .endpoint, "Saisissez le point d'accès.")
            require(bucket, .bucket, "Saisissez le nom du bucket.")
            require(accessKey, .accessKey, "Saisissez la clé d'accès.")
            if !editing { require(secretKey, .secretKey, "Saisissez la clé secrète.") }
        case .server:
            require(address, .address, "Saisissez l'adresse du serveur.")
        }
        if encrypt { require(encryptionPassword, .encryptionPassword, "Saisissez une phrase secrète de chiffrement.") }
        return errors
    }

    /// The address as a URL for WebDAV: https by default, with the port when it is not the scheme's own.
    private var serverURL: String {
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text) else { return text }
        let standard = components.scheme == "http" ? 80 : 443
        if components.port == nil, let port = Int(port), port != standard { components.port = port }
        return components.string ?? text
    }

    /// The host name alone, for SFTP, FTP and SMB.
    private var host: String {
        var text = address.trimmingCharacters(in: .whitespaces)
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let colon = text.lastIndex(of: ":"), !text.contains("]") { text = String(text[..<colon]) }
        return text
    }
}
