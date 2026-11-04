import SwiftUI

/// A storage service CloudShelf can mount, in the order of the add dialog.
struct Provider: Identifiable, Hashable {
    enum Kind {
        /// Authorized in the browser.
        case oauth
        /// E-mail and password.
        case login
        case s3
        /// Address, port and credentials.
        case server
    }

    enum Glyph: Hashable {
        /// The service's logo in its own colours, drawn at 70 % of a white tile.
        case brand(String)
        /// An outline icon, drawn at 54 % of the tile.
        case icon(String)
    }

    let id: String
    let name: String
    let subtitle: String
    let color: Color
    let glyph: Glyph
    let kind: Kind
    /// The rclone backend behind it.
    let type: String
    var vendor: String?
    var port: Int?
    var hostPlaceholder = ""
    var web: URL?

    static let all: [Provider] = [
        Provider(id: "webdav", name: "WebDAV", subtitle: "Serveurs WebDAV", color: Color(hex: 0x5E5CE6), glyph: .icon("tile-world-www"),
                 kind: .server, type: "webdav", vendor: "other", port: 443, hostPlaceholder: "https://serveur.exemple.fr"),
        Provider(id: "gdrive", name: "Google Drive", subtitle: "Google Workspace", color: Color(hex: 0x1A73E8), glyph: .brand("brand-googledrive"),
                 kind: .oauth, type: "drive", web: URL(string: "https://drive.google.com")),
        Provider(id: "onedrive", name: "OneDrive", subtitle: "Personnel et professionnel", color: Color(hex: 0x0364B8), glyph: .brand("brand-onedrive"),
                 kind: .oauth, type: "onedrive", web: URL(string: "https://onedrive.live.com")),
        Provider(id: "dropbox", name: "Dropbox", subtitle: "Personnel et Business", color: Color(hex: 0x0061FF), glyph: .brand("brand-dropbox"),
                 kind: .oauth, type: "dropbox", web: URL(string: "https://www.dropbox.com/home")),
        Provider(id: "box", name: "Box", subtitle: "Box.com", color: Color(hex: 0x0061D5), glyph: .brand("brand-box"),
                 kind: .oauth, type: "box", web: URL(string: "https://app.box.com")),
        Provider(id: "mega", name: "MEGA", subtitle: "mega.io", color: Color(hex: 0xD9272E), glyph: .brand("brand-mega"),
                 kind: .login, type: "mega", web: URL(string: "https://mega.nz")),
        Provider(id: "proton", name: "Proton Drive", subtitle: "Chiffré de bout en bout", color: Color(hex: 0x6D4AFF), glyph: .brand("brand-protondrive"),
                 kind: .login, type: "protondrive", web: URL(string: "https://drive.proton.me")),
        Provider(id: "kdrive", name: "kDrive", subtitle: "Infomaniak", color: Color(hex: 0x0098FF), glyph: .brand("brand-kdrive"),
                 kind: .server, type: "webdav", vendor: "other", port: 443, hostPlaceholder: "https://123456.connect.kdrive.infomaniak.com",
                 web: URL(string: "https://kdrive.infomaniak.com")),
        Provider(id: "s3", name: "Compatible S3", subtitle: "AWS, Backblaze, Wasabi, R2", color: Color(hex: 0xF08C00), glyph: .icon("tile-bucket"),
                 kind: .s3, type: "s3"),
        Provider(id: "sftp", name: "SFTP", subtitle: "SFTP / SSH", color: Color(hex: 0x3A3A3C), glyph: .icon("tile-terminal-2"),
                 kind: .server, type: "sftp", port: 22, hostPlaceholder: "serveur.exemple.fr"),
        Provider(id: "ftp", name: "FTP", subtitle: "FTP et FTPS", color: Color(hex: 0x8E8E93), glyph: .icon("tile-folder-share"),
                 kind: .server, type: "ftp", port: 21, hostPlaceholder: "ftp.exemple.fr"),
        Provider(id: "smb", name: "SMB", subtitle: "Partages Windows et NAS", color: Color(hex: 0x30B0C7), glyph: .icon("tile-share-2"),
                 kind: .server, type: "smb", port: 445, hostPlaceholder: "nas.local"),
        Provider(id: "synology", name: "Synology", subtitle: "NAS Synology", color: Color(hex: 0x2B2B2D), glyph: .icon("tile-server-2"),
                 kind: .server, type: "webdav", vendor: "other", port: 5006, hostPlaceholder: "https://nas.local"),
        Provider(id: "qnap", name: "QNAP", subtitle: "NAS QNAP", color: Color(hex: 0x0C2E82), glyph: .icon("tile-server"),
                 kind: .server, type: "webdav", vendor: "other", port: 443, hostPlaceholder: "https://nas.local"),
        Provider(id: "nextcloud", name: "Nextcloud", subtitle: "Nextcloud et ownCloud", color: Color(hex: 0x0082C9), glyph: .brand("brand-nextcloud"),
                 kind: .server, type: "webdav", vendor: "nextcloud", port: 443, hostPlaceholder: "https://cloud.exemple.fr")
    ]

    static func named(_ id: String) -> Provider {
        all.first { $0.id == id } ?? Provider(id: id, name: id, subtitle: "", color: Color(hex: 0x8E8E93), glyph: .icon("tile-server"),
                                              kind: .server, type: id)
    }

    /// The closest entry for a remote found in rclone.conf.
    static func matching(type: String, vendor: String?, url: String?) -> Provider {
        switch type {
        case "drive": return named("gdrive")
        case "protondrive": return named("proton")
        case "webdav":
            if vendor == "nextcloud" || vendor == "owncloud" { return named("nextcloud") }
            if url?.contains("kdrive.infomaniak") == true { return named("kdrive") }
            return named("webdav")
        default:
            return all.first { $0.type == type && $0.id == type } ?? named(type)
        }
    }

    /// How the connection is described on the drive page.
    var connectionHint: String {
        kind == .oauth ? "autorisé via le navigateur" : "identifiants dans rclone.conf, masqués"
    }
}
