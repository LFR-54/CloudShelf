import Foundation

enum MountState: Equatable {
    case unmounted
    case mounting
    case mounted
    case unmounting
    case failed(String)
}

enum Profile: String, Codable, CaseIterable {
    case streaming = "Streaming"
    case documents = "Documents"
    case backup = "Sauvegarde"

    var hint: String {
        switch self {
        case .streaming: "Lecture anticipée et lectures parallèles. Pour Emby, Plex, Jellyfin."
        case .documents: "Fichiers mis en cache à l'ouverture, écritures envoyées en arrière-plan."
        case .backup: "Cache vidé cinq minutes après usage. Pour les copies volumineuses."
        }
    }
}

enum MountMethod: String, Codable, CaseIterable {
    case macFUSE = "macFUSE"
    case nfs = "NFS intégré"

    var hint: String {
        switch self {
        case .macFUSE: MacFUSE.version == nil
            ? "macFUSE n'est pas installé sur ce Mac."
            : "Extension noyau. Les fichiers lus ne sont pas copiés sur le disque, sauf en profil Documents."
        case .nfs: "Client NFS de macOS, aucune installation. Les fichiers lus sont copiés dans le cache."
        }
    }

    var badge: String { self == .macFUSE ? "FUSE" : "NFS" }
    var isAvailable: Bool { self == .nfs || MacFUSE.version != nil }
}

/// Per-drive choices, applied at the next mount unless noted.
struct DriveSettings: Codable, Equatable {
    var profile = Profile.streaming
    var cacheMaxGB = 20
    /// Mo/s, 0 for no limit. Applied live.
    var limitDown = 0
    var limitUp = 0
    var readOnly = true
    var mountAtLogin = false
    var autoReconnect = true
    var hideMacFiles = true
    var method = MountMethod.nfs
    var timeout = 300
    var skipCertificateCheck = false
    var extraOptions = ""
    /// Folder holding the mount point; nil for ~/Cloud.
    var parentFolder: String?
    var lastRefresh: Date?
}

/// What CloudShelf stores about a drive; the rclone remote holds the connection.
struct DriveRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var remote: String
    /// Path inside the remote, such as an S3 bucket or an SMB share.
    var path = ""
    var name: String
    var provider: String
    var account: String?
    /// Remotes written to rclone.conf by CloudShelf, removed with the drive.
    var createdRemotes: [String] = []
    var settings = DriveSettings()
}

struct Upload: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let bytes: Int64
    let size: Int64
    let speed: Double

    var fileName: String { (name as NSString).lastPathComponent }
    var folder: String { (name as NSString).deletingLastPathComponent }
    var progress: Double { size > 0 ? Double(bytes) / Double(size) : 0 }
}

struct SpeedTest: Equatable {
    var progress = 0.0
    var speed: Double?
    var latency: Int?
    var error: String?

    var isRunning: Bool { speed == nil && error == nil }
}

@MainActor @Observable
final class Drive: Identifiable {
    var record: DriveRecord
    var state: MountState = .unmounted
    var readSpeed = 0.0
    var writeSpeed = 0.0
    var space: Space?
    /// Read throughput of the last 60 seconds, oldest first.
    var history = Array(repeating: 0.0, count: 60)
    /// Write throughput of the last 60 seconds, oldest first.
    var writeHistory = Array(repeating: 0.0, count: 60)
    var uploads: [Upload] = []
    /// Files rclone is uploading or has queued; once unmounted, those left in the cache, which leave at the next mount.
    var pendingUploads = 0
    var cacheBytes: Int64 = 0
    /// Something the app did on its own, such as emptying the cache.
    var notice: String?
    var speedTest: SpeedTest?

    init(record: DriveRecord) {
        self.record = record
        id = record.id
    }

    let id: String
    var name: String { record.name }
    var remote: String { record.remote }
    var settings: DriveSettings { record.settings }
    var provider: Provider { Provider.named(record.provider) }
    var remoteSpec: String { "\(record.remote):\(record.path)" }
    var isMounted: Bool { state == .mounted }
    var isBusy: Bool { state == .mounting || state == .unmounting }
    var account: String { record.account ?? "\(record.remote):\(record.path)" }

    var mountParent: URL {
        record.settings.parentFolder.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Cloud", directoryHint: .isDirectory)
    }

    var mountPoint: URL { mountParent.appending(path: name, directoryHint: .isDirectory) }

    /// The mount point with the home folder written as ~.
    var displayPath: String { Self.abbreviate(mountPoint.path(percentEncoded: false)) }

    var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/CloudShelf", directoryHint: .isDirectory)
            .appending(path: "\(id).log")
    }

    var errorMessage: String? {
        if case .failed(let message) = state { message } else { nil }
    }

    var status: (kind: StatusKind, label: String) {
        switch state {
        case .mounted: writeSpeed >= Format.idleThreshold ? (.busy, "Envoi en cours") : (.on, "Monté")
        case .mounting: (.busy, "Montage…")
        case .unmounting: (.busy, "Démontage…")
        case .failed: (.error, "Erreur")
        case .unmounted: (.off, "Non monté")
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return trimmed.hasPrefix(home) ? "~/" + trimmed.dropFirst(home.count).drop { $0 == "/" } : trimmed
    }
}

/// rclone flags for a drive.
/// Measured on Dropbox: NFS reads need the full disk cache, and 16 MiB chunks on 4 streams give the quickest
/// seeks and the steadiest concurrent playback; smaller chunks hit Dropbox's request limit.
/// Over macFUSE, reads straight from the network play as smoothly as NFS from its cache, with nothing written to disk.
enum MountOptions {
    static let defaultCacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "CloudShelf", directoryHint: .isDirectory)

    /// Each drive has its own cache folder, so two drives on one remote never share it.
    @MainActor
    static func cacheDirectory(for drive: Drive, base: URL) -> URL {
        base.appending(path: drive.id, directoryHint: .isDirectory)
    }

    /// NFS cannot read without the full cache. macFUSE keeps the cache for writes only, except for documents,
    /// which are worth keeping on disk once opened.
    static func readsBypassCache(_ settings: DriveSettings) -> Bool {
        settings.method == .macFUSE && settings.profile != .documents
    }

    /// The bundled rclone (rclone-patches) can share streams between the files being read.
    static let sharedStreams = Rclone.locate()?.isBundled ?? false

    /// Direct reads use 32 MiB chunks: on Dropbox they doubled single-file speed over 16 MiB with the same seeks.
    /// Dropbox refuses more than about 16 downloads at once per account. Shared, 16 streams give one file
    /// 60-80 MB/s and split evenly between several. Without sharing, more than 4 per file gets throttled as soon as
    /// several are read, so only the backup profile, made for copying one large file at a time, uses 16.
    static func profileFlags(_ settings: DriveSettings) -> [String] {
        let direct = readsBypassCache(settings)
        let streams = sharedStreams
            ? ["--vfs-read-chunk-streams", "16", "--vfs-read-chunk-streams-total", "16"]
            : ["--vfs-read-chunk-streams", settings.profile == .backup ? "16" : "4"]
        let chunks = ["--vfs-read-chunk-size", direct ? "32M" : "16M"] + streams
        return switch settings.profile {
        case .streaming: chunks + ["--buffer-size", "64M"] + (direct ? [] : ["--vfs-read-ahead", "512M"])
        case .documents: chunks + ["--buffer-size", "16M"]
        case .backup: chunks + ["--buffer-size", "16M", "--vfs-cache-max-age", "5m"]
        }
    }

    /// "UPLOAD:DOWNLOAD" for --bwlimit and core/bwlimit, in bytes per second.
    static func bandwidth(_ settings: DriveSettings) -> String? {
        guard settings.limitDown > 0 || settings.limitUp > 0 else { return nil }
        func side(_ megabytes: Int) -> String { megabytes > 0 ? "\(megabytes * 1_000_000)B" : "off" }
        return "\(side(settings.limitUp)):\(side(settings.limitDown))"
    }

    @MainActor
    static func arguments(for drive: Drive, cacheBase: URL) -> [String] {
        let settings = drive.settings
        var flags = [
            "--cache-dir", cacheDirectory(for: drive, base: cacheBase).path,
            "--vfs-cache-mode", readsBypassCache(settings) ? "writes" : "full",
            "--vfs-cache-max-size", "\(settings.cacheMaxGB)G",
            "--vfs-cache-min-free-space", "10G",
            "--vfs-cache-poll-interval", "30s",
            "--dir-cache-time", "1h",
            "--poll-interval", "1m",
            "--timeout", "\(settings.timeout)s"
        ] + profileFlags(settings)
        if settings.readOnly { flags.append("--read-only") }
        if settings.hideMacFiles { flags += ["--exclude", "._*", "--exclude", ".DS_Store"] }
        if let bandwidth = bandwidth(settings) { flags += ["--bwlimit", bandwidth] }
        if settings.skipCertificateCheck { flags.append("--no-check-certificate") }
        // Measured on Dropbox: 128 MiB chunks sent a 1 GB file in 31 s against 56 s with the 48 MiB default, and
        // 16 uploads at once (each batch then commits 16 files) sent 50 small files in 15 s against 40 s with 4,
        // without throttling, even while reading. Up to 2 GiB of memory with 16 large files in flight.
        if drive.provider.type == "dropbox", !settings.readOnly {
            flags += ["--dropbox-chunk-size", "128M", "--transfers", "16"]
        }
        return flags + extraOptions(settings.extraOptions)
    }

    /// The flags shown on the drive page: the profile's, then the user's own.
    static func summary(_ settings: DriveSettings) -> String {
        let profile = profileFlags(settings).dropFirst(2).joined(separator: " ")
        return settings.extraOptions.isEmpty ? profile : profile + " " + settings.extraOptions
    }

    /// Splits user flags on spaces, keeping quoted values together.
    static func extraOptions(_ text: String) -> [String] {
        var words: [String] = [], current = "", quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

enum MacFUSE {
    /// The installed version, read from its bundle.
    static let version: String? = {
        let plist = URL(filePath: "/Library/Filesystems/macfuse.fs/Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String)
    }()
}
