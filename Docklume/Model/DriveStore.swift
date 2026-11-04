import AppKit
import UserNotifications

/// The drives, their mount processes, live throughput and the operations of the drive pages.
@MainActor @Observable
final class DriveStore {
    private(set) var drives: [Drive] = []
    private(set) var engineVersion: String?

    /// The rclone release, without the suffix of the build bundled with Docklume.
    var engineRelease: String? { engineVersion?.components(separatedBy: "-docklume").first }
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var remotes: [Remote] = []
    private(set) var configPath: String?
    let preferences: Preferences

    @ObservationIgnored private var rclone: Rclone?
    @ObservationIgnored private var sessions: [Drive.ID: MountSession] = [:]
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var speedTests: [Drive.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var reconnects: [Drive.ID: Int] = [:]
    @ObservationIgnored private var warnedFull: Set<Drive.ID> = []
    @ObservationIgnored private var warnedDiskFull = false
    @ObservationIgnored private var scannedCaches: [Drive.ID: Int64] = [:]
    /// When the Finder announced the eject of a drive's volume.
    @ObservationIgnored private var ejections: [Drive.ID: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var ejectObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshingSpace = false
    @ObservationIgnored private var tagSignature: String?
    @ObservationIgnored private var syncingTags = false
    @ObservationIgnored private let catalog: URL?

    static let catalogURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Docklume/drives.json")

    init(preferences: Preferences = Preferences(), catalog: URL? = DriveStore.catalogURL) {
        self.preferences = preferences
        self.catalog = catalog
    }

    /// A store showing given drives without rclone, for screenshots.
    init(showing drives: [Drive], preferences: Preferences, engineVersion: String) {
        self.preferences = preferences
        self.catalog = nil
        self.drives = drives
        self.engineVersion = engineVersion
    }

    var mountedCount: Int { drives.filter(\.isMounted).count }
    var totalRead: Double { drives.reduce(0) { $0 + $1.readSpeed } }
    var totalWrite: Double { drives.reduce(0) { $0 + $1.writeSpeed } }
    var hasActiveMounts: Bool { !sessions.isEmpty }
    var pendingUploadCount: Int { drives.reduce(0) { $0 + $1.pendingUploads } }

    /// What happens to files still being uploaded when the drives are unmounted.
    static func unsentMessage(_ count: Int) -> String {
        "\(Format.plural(count, "fichier")) n'\(count > 1 ? "ont" : "a") pas fini d'être envoyé\(count > 1 ? "s" : ""). L'envoi reprendra au prochain montage du lecteur."
    }
    var uploads: [(drive: Drive, upload: Upload)] { drives.flatMap { drive in drive.uploads.map { (drive, $0) } } }
    var totalCacheBytes: Int64 { drives.reduce(0) { $0 + $1.cacheBytes } }
    var totalCacheMaxGB: Int { drives.reduce(0) { $0 + $1.settings.cacheMaxGB } }

    /// Read throughput of all drives over the last minute.
    var readHistory: [Double] { total(\.history) }
    var writeHistory: [Double] { total(\.writeHistory) }

    private func total(_ series: KeyPath<Drive, [Double]>) -> [Double] {
        (0..<60).map { index in drives.reduce(0) { $0 + ($1[keyPath: series].indices.contains(index) ? $1[keyPath: series][index] : 0) } }
    }

    /// Remotes of rclone.conf that no drive uses yet.
    var importableRemotes: [Remote] {
        remotes.filter { remote in !drives.contains { $0.remote == remote.name || $0.record.createdRemotes.contains(remote.name) } }
    }

    func drive(_ id: String) -> Drive? { drives.first { $0.id == id } }

    // MARK: Loading

    func load() async {
        guard let rclone = Rclone.locate() else {
            loadError = RcloneError.notFound.localizedDescription
            return
        }
        self.rclone = rclone
        isLoading = true
        defer { isLoading = false }
        do {
            engineVersion = try await rclone.version()
            configPath = try? await rclone.configFile()
            remotes = try await rclone.remotes()
            if let saved = readCatalog() {
                drives = saved.map(Drive.init)
            } else {
                // First launch: every remote of rclone.conf becomes a drive, unmounted and read-only.
                let dump = (try? await rclone.dump()) ?? [:]
                drives = []
                for remote in remotes { drives.append(Drive(record: importedRecord(remote, dump: dump))) }
                save()
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        watchEjections()
        adoptOrphans()
        startPolling()
        for drive in drives where drive.settings.mountAtLogin { mount(drive) }
        await refreshSpace()
        await lookUpAccounts()
    }

    func importRemotes() async -> Int {
        guard let rclone else { return 0 }
        remotes = (try? await rclone.remotes()) ?? remotes
        let dump = (try? await rclone.dump()) ?? [:]
        let fresh = importableRemotes
        for remote in fresh { drives.append(Drive(record: importedRecord(remote, dump: dump))) }
        save()
        await refreshSpace()
        await lookUpAccounts()
        return fresh.count
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(drives.map(\.record)).write(to: url, options: .atomic)
    }

    private func importedRecord(_ remote: Remote, dump: [String: [String: String]]) -> DriveRecord {
        let parameters = dump[remote.name] ?? [:]
        let provider = Provider.matching(type: remote.type, vendor: parameters["vendor"], url: parameters["url"])
        var record = DriveRecord(remote: remote.name, name: freeName(provider.name), provider: provider.id)
        record.settings.profile = remote.type == "dropbox" ? .streaming : .documents
        record.settings.cacheMaxGB = remote.type == "dropbox" ? 200 : 20
        record.account = parameters["user"] ?? parameters["username"]
        return record
    }

    private func readCatalog() -> [DriveRecord]? {
        guard let catalog, let data = try? Data(contentsOf: catalog) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([DriveRecord].self, from: data)
    }

    private func save() {
        guard let catalog else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: catalog.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(drives.map(\.record)).write(to: catalog, options: .atomic)
    }

    private func refreshSpace() async {
        guard let rclone, !refreshingSpace else { return }
        refreshingSpace = true
        defer { refreshingSpace = false }
        await withTaskGroup(of: (String, Space?, String?).self) { group in
            for drive in drives {
                let id = drive.id, spec = drive.remoteSpec
                group.addTask {
                    let (space, error) = await Self.space(of: spec, rclone)
                    return (id, space, error)
                }
            }
            for await (id, space, error) in group {
                guard let drive = drive(id) else { continue }
                show(space, error, on: drive)
            }
        }
    }

    private func readSpace(_ drive: Drive) async {
        guard let rclone else { return }
        let (space, error) = await Self.space(of: drive.remoteSpec, rclone)
        show(space, error, on: drive)
    }

    private func show(_ space: Space?, _ error: String?, on drive: Drive) {
        drive.space = space
        drive.spaceError = error.map { RcloneLog.explain($0, provider: drive.provider.id) }
        warnIfNearlyFull(drive)
    }

    /// The space of a remote, or why it could not be read; a service that does not report it gets an empty Space.
    nonisolated private static func space(of spec: String, _ rclone: Rclone) async -> (Space?, String?) {
        do {
            return (try await rclone.about(spec), nil)
        } catch {
            let message = error.localizedDescription
            return message.contains("doesn't support about") ? (Space(total: nil, used: nil, free: nil), nil) : (nil, message)
        }
    }

    /// Fills in the e-mail of OAuth drives; `about` has just refreshed their tokens.
    private func lookUpAccounts() async {
        guard let rclone, drives.contains(where: { $0.record.account == nil && $0.provider.kind == .oauth }),
              let dump = try? await rclone.dump() else { return }
        for drive in drives where drive.record.account == nil && drive.provider.kind == .oauth {
            guard let token = dump[drive.remote]?["token"],
                  let email = await AccountLookup.email(type: drive.provider.type, token: token) else { continue }
            drive.record.account = email
        }
        save()
    }

    // MARK: Mounting

    func mount(_ drive: Drive) {
        guard let rclone, sessions[drive.id] == nil else { return }
        guard drive.settings.method.isAvailable else {
            drive.state = .failed("macFUSE n'est pas installé. Choisissez NFS intégré dans la fiche du lecteur.")
            return
        }
        // Mounting over another volume would hide it, and its rclone may be using the same cache.
        guard !Mounts.isMounted(drive.mountPoint) else {
            return fail(drive, "Un autre montage occupe déjà \(drive.displayPath). Démontez-le, puis réessayez.")
        }
        drive.state = .mounting
        drive.notice = nil
        ejections[drive.id] = nil
        do {
            // A mount point left by a process that did not exit cleanly stays busy; a new directory does not.
            removeMountPoint(drive)
            try FileManager.default.createDirectory(at: drive.mountPoint, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: drive.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            RcloneLog.rotate(drive.logFile)
            let session = try MountSession(rclone: rclone, command: drive.settings.method == .macFUSE ? "mount" : "nfsmount",
                                           remote: drive.remoteSpec, volumeName: drive.name, mountPoint: drive.mountPoint,
                                           options: MountOptions.arguments(for: drive, cacheBase: preferences.cacheBase), logFile: drive.logFile)
            watch(drive, session)
            Task { await waitUntilMounted(drive, session) }
        } catch {
            fail(drive, error.localizedDescription)
        }
    }

    private func watch(_ drive: Drive, _ session: MountSession) {
        session.onExit = { [weak self, weak drive, weak session] status in
            guard let self, let drive, let session else { return }
            Task { await self.sessionEnded(drive, session, status: status) }
        }
        sessions[drive.id] = session
    }

    /// Takes over the drives that a previous run left mounted when it crashed or was forced to quit, so they keep
    /// serving their files and their cache is never used by two rclone processes.
    private func adoptOrphans() {
        let orphans = OrphanMount.all()
        for drive in drives where sessions[drive.id] == nil {
            let cache = MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase).path
            guard let orphan = orphans.first(where: { $0.cacheDirectory == cache }) else { continue }
            let session = MountSession(adopting: orphan, logFile: drive.logFile)
            watch(drive, session)
            if Mounts.same(orphan.mountPoint, drive.mountPoint), Mounts.isMounted(drive.mountPoint) {
                drive.state = .mounted
                drive.notice = "Montage repris : Docklume s'était arrêté sans démonter ce lecteur."
            } else {
                drive.state = .unmounting
                stop(drive, session)
            }
        }
    }

    /// The Finder and Disk Utility announce an eject; the unmounts of Docklume do not.
    private func watchEjections() {
        guard ejectObserver == nil else { return }
        ejectObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let volume = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                for drive in self.drives where drive.isMounted && Mounts.same(drive.mountPoint, volume) {
                    self.ejections[drive.id] = .now
                }
            }
        }
    }

    func unmount(_ drive: Drive) {
        guard let session = sessions[drive.id] else {
            // Waiting to mount again: stops waiting.
            if drive.state == .mounting {
                drive.state = .unmounted
                drive.notice = nil
            }
            return
        }
        drive.state = .unmounting
        stop(drive, session)
    }

    /// Stops rclone, forcing it after 20 s. A process stuck in the kernel as it exits never reports its end, so the
    /// session is let go 10 s later, by when its volume is gone.
    private func stop(_ drive: Drive, _ session: MountSession) {
        session.stop()
        Task {
            try? await Task.sleep(for: .seconds(20))
            guard sessions[drive.id] === session else { return }
            await session.forceStop()
            try? await Task.sleep(for: .seconds(10))
            session.abandon()
        }
    }

    func toggleMount(_ drive: Drive) {
        drive.isMounted || drive.state == .mounting ? unmount(drive) : mount(drive)
    }

    /// Unmounts everything, forcing what is still mounted after 15 s.
    func unmountAll() async {
        drives.filter { sessions[$0.id] != nil || $0.state == .mounting }.forEach(unmount)
        let deadline = ContinuousClock.now + .seconds(15)
        while !sessions.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        for session in sessions.values { await session.forceStop() }
    }

    /// Stops the drive, applies a change while nothing is mounted, then mounts it again if it was.
    func remount(_ drive: Drive, change: () -> Void = {}) async {
        let wasMounted = sessions[drive.id] != nil
        if wasMounted {
            unmount(drive)
            while sessions[drive.id] != nil { try? await Task.sleep(for: .milliseconds(200)) }
        }
        change()
        if wasMounted { mount(drive) }
    }

    /// rclone retries a slow or throttled server for about two minutes, then exits with the cause, so the wait lasts
    /// as long as rclone does; the deadline only catches a mount that hangs.
    private func waitUntilMounted(_ drive: Drive, _ session: MountSession) async {
        let start = ContinuousClock.now
        var notice: String?
        defer { if let notice, drive.notice == notice { drive.notice = nil } }
        while ContinuousClock.now < start + .seconds(180), session.isRunning, drive.state == .mounting {
            if Mounts.isMounted(drive.mountPoint) {
                drive.state = .mounted
                reconnects[drive.id] = nil
                return
            }
            if notice == nil, drive.notice == nil, ContinuousClock.now > start + .seconds(10) {
                notice = await slowMountNotice(drive)
                drive.notice = notice
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if drive.state == .mounting, session.isRunning {
            fail(drive, "Le volume n'est pas apparu après 3 minutes.")
            stop(drive, session)
        }
    }

    /// rclone's own Google key is shared by all its users, and Google throttles it when they are too many at once.
    private func slowMountNotice(_ drive: Drive) async -> String {
        let config = drive.provider.type == "drive" ? (try? await rclone?.dump())?[drive.remote] : nil
        return config?["client_id", default: ""].isEmpty == true
            ? "Google limite la clé partagée de rclone, nouvelle tentative en cours. Votre propre clé, dans la fiche du lecteur, évite cette attente."
            : "Le serveur tarde à répondre. rclone réessaie, ce qui peut prendre deux minutes."
    }

    /// Removes the mount point folder unless something is mounted on it or it holds files.
    private func removeMountPoint(_ drive: Drive) {
        guard !Mounts.isMounted(drive.mountPoint) else { return }
        // The Finder drops a .DS_Store in the folder once the volume is gone; rmdir removes nothing else.
        try? FileManager.default.removeItem(at: drive.mountPoint.appending(path: ".DS_Store"))
        rmdir(drive.mountPoint.path)
    }

    /// The session is released only once its mount point is clean, so a new mount cannot race the cleanup.
    private func sessionEnded(_ drive: Drive, _ session: MountSession, status: Int32?) async {
        guard sessions[drive.id] === session else { return }
        // A process that died leaves a dead NFS mount behind, which stalls the Finder.
        if Mounts.isMounted(drive.mountPoint) { await Mounts.unmount(drive.mountPoint, force: true) }
        removeMountPoint(drive)
        sessions[drive.id] = nil
        let ejected = ejections.removeValue(forKey: drive.id).map { ContinuousClock.now - $0 < .seconds(60) } ?? false
        drive.readSpeed = 0
        drive.writeSpeed = 0
        drive.uploads = []
        func failure() -> String {
            RcloneLog.lastError(at: drive.logFile, after: session.logOffset)
                ?? status.map { "rclone s'est arrêté (code \($0))." } ?? "rclone s'est arrêté."
        }
        switch drive.state {
        case .failed:
            break
        case .unmounting, .unmounted:
            drive.state = .unmounted
            drive.notice = nil
        case .mounting:
            let message = failure()
            let attempts = reconnects[drive.id, default: 0]
            // rclone gives up at once when it cannot reach the server, which happens at login before the network is up.
            if drive.settings.autoReconnect, attempts < 5, RcloneLog.isNetworkError(message) {
                reconnects[drive.id] = attempts + 1
                let delay = 5 << attempts
                await mountAgain(drive, after: delay, "Serveur injoignable, nouvelle tentative dans \(delay) s…")
            } else {
                reconnects[drive.id] = nil
                fail(drive, message)
            }
        case .mounted where ejected:
            // rclone exits by itself once its volume is ejected from the Finder.
            drive.state = .unmounted
            drive.notice = nil
        case .mounted:
            let attempts = reconnects[drive.id, default: 0]
            if drive.settings.autoReconnect, attempts < 3 {
                reconnects[drive.id] = attempts + 1
                await mountAgain(drive, after: 5, "rclone s'est arrêté, nouvelle tentative de montage…")
                if drive.state == .mounting, sessions[drive.id] != nil { drive.notice = "Remonté automatiquement après l'arrêt de rclone." }
            } else {
                fail(drive, failure())
            }
        }
    }

    /// Mounts the drive again after `delay` seconds, saying why meanwhile. Unmounting or deleting the drive stops the wait.
    private func mountAgain(_ drive: Drive, after delay: Int, _ notice: String) async {
        drive.state = .mounting
        drive.notice = notice
        try? await Task.sleep(for: .seconds(delay))
        guard drive.state == .mounting, sessions[drive.id] == nil, drives.contains(where: { $0 === drive }) else { return }
        mount(drive)
    }

    private func fail(_ drive: Drive, _ message: String) {
        let message = RcloneLog.explain(message, provider: drive.provider.id)
        drive.state = .failed(message)
        let lowered = message.lowercased()
        let expired = lowered.contains("token") && ["expired", "invalid_grant", "unauthorized", "401"].contains { lowered.contains($0) }
        if expired, preferences.notifySessionExpired {
            notify("Session expirée : \(drive.name)", "Reconnectez le lecteur depuis sa fiche.")
        } else if preferences.notifyMountFailure {
            notify("Échec du montage de « \(drive.name) »", message)
        }
    }

    // MARK: Drive operations

    func nameError(_ value: String, except id: String? = nil) -> String? {
        let name = value.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Saisissez un nom." }
        if name.contains("/") || name.contains(":") { return "Le nom ne peut pas contenir « / » ni « : »." }
        // The name is the folder of the mount point: "." or ".." would mount over its parent.
        if name.hasPrefix(".") { return "Le nom ne peut pas commencer par un point." }
        if name.compare(TagShortcuts.root.lastPathComponent, options: .caseInsensitive) == .orderedSame {
            return "« \(TagShortcuts.root.lastPathComponent) » est réservé au dossier des tags, dans ~/Cloud."
        }
        if drives.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) { return "Un lecteur porte déjà ce nom." }
        return nil
    }

    func freeName(_ base: String) -> String {
        guard nameError(base) != nil else { return base }
        var number = 2
        while nameError("\(base) \(number)") != nil { number += 1 }
        return "\(base) \(number)"
    }

    /// Renames the drive; a mounted volume is remounted under the new name. Returns the error to show, if any.
    @discardableResult
    func rename(_ drive: Drive, to value: String) -> String? {
        if let error = nameError(value, except: drive.id) { return error }
        let name = value.trimmingCharacters(in: .whitespaces)
        guard name != drive.name else { return nil }
        Task {
            await remount(drive) { drive.record.name = name }
            save()
        }
        return nil
    }

    func move(_ drive: Drive, to folder: URL?) {
        Task {
            await remount(drive) { drive.record.settings.parentFolder = folder?.path(percentEncoded: false) }
            save()
        }
    }

    func duplicate(_ drive: Drive) -> Drive {
        var record = drive.record
        record.id = UUID().uuidString
        record.name = freeName("\(drive.name) copie")
        record.settings.lastRefresh = nil
        record.settings.mountAtLogin = false
        let copy = Drive(record: record)
        copy.space = drive.space
        drives.insert(copy, at: (drives.firstIndex { $0 === drive } ?? drives.count - 1) + 1)
        save()
        return copy
    }

    /// What deleting a drive does to rclone.conf.
    func deletionMessage(_ drive: Drive) -> String {
        !removesRemote(drive)
            ? "Le volume est démonté et le lecteur retiré de Docklume. Le remote « \(drive.remote) » reste dans rclone.conf. Les fichiers dans le cloud ne sont pas touchés."
            : "Le volume est démonté et sa configuration supprimée. Les fichiers dans le cloud ne sont pas touchés."
    }

    /// Files written to the drive that rclone has not uploaded yet; they exist only in its cache.
    func pendingUploads(_ drive: Drive) -> CacheFolder.Pending {
        CacheFolder.pending(in: MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase))
    }

    static func pendingMessage(_ drive: Drive, _ pending: CacheFolder.Pending) -> String {
        "« \(drive.name) » a encore \(Format.plural(pending.files, "fichier")) à envoyer (\(Format.capacity(pending.bytes))). "
            + "Montez-le et attendez la fin des envois avant de le supprimer."
    }

    /// Refuses while files are waiting to be uploaded, since deleting the drive deletes its cache.
    func delete(_ drive: Drive) async throws {
        if pendingUploads(drive).files > 0 { throw RcloneError.command(Self.pendingMessage(drive, pendingUploads(drive))) }
        cancelSpeedTest(drive)
        if sessions[drive.id] != nil {
            unmount(drive)
            while sessions[drive.id] != nil { try? await Task.sleep(for: .milliseconds(200)) }
        }
        // A file written while the drive was being stopped.
        let pending = pendingUploads(drive)
        if pending.files > 0 { throw RcloneError.command(Self.pendingMessage(drive, pending)) }
        drives.removeAll { $0 === drive }
        save()
        try? FileManager.default.removeItem(at: MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase))
        try? FileManager.default.removeItem(at: drive.logFile)
        try? FileManager.default.removeItem(at: RcloneLog.previousLog(of: drive.logFile))
        if removesRemote(drive) {
            for remote in drive.record.createdRemotes.reversed() { try? await rclone?.deleteRemote(remote) }
        }
        remotes = (try? await rclone?.remotes()) ?? remotes
    }

    /// A remote Docklume created goes with the last drive using it; a duplicate shares it.
    private func removesRemote(_ drive: Drive) -> Bool {
        !drive.record.createdRemotes.isEmpty && !drives.contains { $0 !== drive && $0.remote == drive.remote }
    }

    /// Changes a setting; the bandwidth limit also applies to a mounted drive right away.
    func update(_ drive: Drive, _ change: (inout DriveSettings) -> Void) {
        let before = drive.settings
        change(&drive.record.settings)
        save()
        if before.limitDown != drive.settings.limitDown || before.limitUp != drive.settings.limitUp, let session = sessions[drive.id] {
            let rate = MountOptions.bandwidth(drive.settings) ?? "off"
            Task { try? await session.call("core/bwlimit", ["rate": rate]) }
        }
    }

    /// Whether a change made now waits for the next mount.
    func appliesLater(_ drive: Drive) -> Bool { sessions[drive.id] != nil }

    func refreshContent(_ drive: Drive) async throws {
        guard let session = sessions[drive.id] else {
            throw RcloneError.command("Montez le lecteur pour actualiser son contenu.")
        }
        try await session.call("vfs/forget")
        drive.record.settings.lastRefresh = .now
        save()
    }

    /// Empties the drive's cache except the files still waiting to be uploaded, which it returns.
    @discardableResult
    func clearCache(_ drive: Drive) async -> CacheFolder.Pending {
        let folder = MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase)
        var kept = CacheFolder.Pending()
        await remount(drive) { kept = CacheFolder.purge(folder) }
        drive.cacheBytes = DiskSpace.allocated(in: folder)
        return kept
    }

    @discardableResult
    func clearAllCaches() async -> CacheFolder.Pending {
        var kept = CacheFolder.Pending()
        for drive in drives {
            let pending = await clearCache(drive)
            kept.files += pending.files
            kept.bytes += pending.bytes
        }
        // Leftovers of drives deleted while the folder was elsewhere.
        let known = Set(drives.map(\.id))
        let folders = (try? FileManager.default.contentsOfDirectory(at: preferences.cacheBase, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !known.contains(folder.lastPathComponent) { CacheFolder.purge(folder) }
        return kept
    }

    /// Moves the caches to another folder, carrying over the files still waiting to be uploaded;
    /// mounted drives are remounted on the new folder.
    func moveCaches(to base: URL) async {
        let old = preferences.cacheBase
        guard base.standardizedFileURL != old.standardizedFileURL else { return }
        preferences.cacheBase = base
        for drive in drives {
            await remount(drive) {
                CacheFolder.move(MountOptions.cacheDirectory(for: drive, base: old), to: MountOptions.cacheDirectory(for: drive, base: base))
            }
            drive.cacheBytes = DiskSpace.allocated(in: MountOptions.cacheDirectory(for: drive, base: base))
        }
    }

    func showInFinder(_ drive: Drive) {
        NSWorkspace.shared.open(drive.isMounted ? drive.mountPoint : drive.mountParent)
    }

    func copyPath(_ drive: Drive) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(drive.mountPoint.path(percentEncoded: false), forType: .string)
    }

    func openWeb(_ drive: Drive) {
        if let web = drive.provider.web { NSWorkspace.shared.open(web) }
    }

    // MARK: Speed test

    func startSpeedTest(_ drive: Drive) {
        speedTests[drive.id]?.cancel()
        drive.speedTest = SpeedTest()
        speedTests[drive.id] = Task { await runSpeedTest(drive) }
    }

    func cancelSpeedTest(_ drive: Drive) {
        speedTests[drive.id]?.cancel()
        speedTests[drive.id] = nil
        drive.speedTest = nil
    }

    private func runSpeedTest(_ drive: Drive) async {
        guard let rclone else { return }
        do {
            var found = try await rclone.firstFile(in: drive.remoteSpec, minimum: 1_000_000_000)
            if found == nil { found = try await rclone.firstFile(in: drive.remoteSpec, minimum: 100_000_000) }
            guard let file = found else {
                throw RcloneError.command("Aucun fichier de plus de 100 Mo à lire sur ce lecteur.")
            }
            let length = min(file.size, 1_000_000_000)
            // A random stretch, so a part already in the cache does not flatter the result.
            let offset = file.size > length ? Int64.random(in: 0...(file.size - length)) / 1_048_576 * 1_048_576 : 0
            let progress: @Sendable (Double) -> Void = { [weak drive] value in
                Task { @MainActor in drive?.speedTest?.progress = value }
            }
            let result = drive.isMounted
                ? try await SpeedProbe.readFile(at: drive.mountPoint.appending(path: file.path), offset: offset, length: length, progress: progress)
                : try await SpeedProbe.readRemote(rclone, path: drive.remoteSpec + (drive.record.path.isEmpty ? "" : "/") + file.path,
                                                  offset: offset, length: length, progress: progress)
            drive.speedTest = SpeedTest(progress: 1, speed: result.speed, latency: result.latency)
        } catch is CancellationError {
            return
        } catch {
            drive.speedTest = SpeedTest(error: error.localizedDescription)
        }
        speedTests[drive.id] = nil
    }

    // MARK: Connections

    /// Opens the browser to authorize the service and returns the token with the account it belongs to.
    /// A token only refreshes with the key that obtained it, so `client` must be the one the remote keeps.
    func authorize(_ provider: Provider, client: OAuthClient? = nil) async throws -> (token: String, account: String?) {
        guard let rclone else { throw RcloneError.notFound }
        let token = try await rclone.authorize(provider.type, client: client)
        return (token, await AccountLookup.email(type: provider.type, token: token))
    }

    /// The user's own app key on the remote behind a drive, nil for rclone's shared one.
    func storedClient(_ drive: Drive) async -> OAuthClient? {
        guard let stored = try? await rclone?.dump()[baseRemote(drive)] else { return nil }
        return OAuthClient(stored: stored)
    }

    /// Signs in again with another app key, or rclone's shared one when nil, then stores the key with the new token
    /// and remounts; nothing changes if the sign-in fails.
    func setClient(_ drive: Drive, _ client: OAuthClient?) async throws -> String {
        guard let rclone else { throw RcloneError.notFound }
        let (token, account) = try await authorize(drive.provider, client: client)
        try await rclone.configure(baseRemote(drive), parameters: ["client_id": client?.id ?? "", "client_secret": client?.secret ?? "", "token": token])
        await remount(drive) {
            if let account { drive.record.account = account }
        }
        save()
        return drive.account
    }

    /// Non-secret parameters of the remote behind a drive, to prefill the edit dialog.
    func storedParameters(_ drive: Drive) async -> [String: String] {
        let secrets: Set = ["pass", "password", "secret_access_key", "token", "2fa", "client_secret"]
        let dump = (try? await rclone?.dump()) ?? [:]
        return (dump[baseRemote(drive)] ?? [:]).filter { !secrets.contains($0.key) }
    }

    /// Tries the connection in a throwaway config, so nothing reaches rclone.conf before Connecter.
    func testConnection(_ draft: ConnectionDraft, editing: Drive?) async throws -> String {
        guard let rclone else { throw RcloneError.notFound }
        let config = FileManager.default.temporaryDirectory.appending(path: "docklume-test-\(UUID().uuidString).conf")
        defer { try? FileManager.default.removeItem(at: config) }
        var parameters = draft.parameters
        if let editing, let stored = try? await rclone.dump()[baseRemote(editing)] {
            parameters = stored.merging(parameters) { $1 }.filter { $0.key != "type" }
        }
        try await rclone.configure("test", type: draft.provider.type, parameters: parameters, config: config)
        let spec = "test:" + draft.remotePath
        if let free = try? await rclone.about(spec, config: config).free {
            return "Connexion réussie · \(Format.capacity(free)) libres"
        }
        do {
            _ = try await rclone.run(["lsf", spec, "--max-depth", "1"], config: config)
        } catch {
            throw RcloneError.command(RcloneLog.explain(error.localizedDescription, provider: draft.provider.id))
        }
        return "Connexion réussie"
    }

    func addDrive(_ draft: ConnectionDraft) async throws -> Drive {
        guard let rclone else { throw RcloneError.notFound }
        let base = uniqueRemoteName(Self.slug(draft.name))
        try await rclone.configure(base, type: draft.provider.type, parameters: draft.parameters)
        var record = DriveRecord(remote: base, path: draft.remotePath, name: draft.name.trimmingCharacters(in: .whitespaces),
                                 provider: draft.provider.id, account: draft.accountLabel, createdRemotes: [base], settings: draft.settings)
        if draft.encrypt {
            let crypt = uniqueRemoteName(base + "-crypt", also: [base])
            do {
                try await rclone.configure(crypt, type: "crypt", parameters: ["remote": "\(base):\(draft.remotePath)", "password": draft.encryptionPassword])
            } catch {
                try? await rclone.deleteRemote(base)
                throw error
            }
            record.remote = crypt
            record.path = ""
            record.createdRemotes.append(crypt)
        }
        remotes = (try? await rclone.remotes()) ?? remotes
        let drive = Drive(record: record)
        drives.append(drive)
        save()
        mount(drive)
        Task { await readSpace(drive) }
        return drive
    }

    func updateConnection(_ drive: Drive, with draft: ConnectionDraft) async throws {
        guard let rclone else { throw RcloneError.notFound }
        let parameters = draft.parameters
        if !parameters.isEmpty { try await rclone.configure(baseRemote(drive), parameters: parameters) }
        let encrypted = drive.record.createdRemotes.count > 1
        await remount(drive) {
            if !encrypted, draft.provider.kind == .s3 || draft.provider.kind == .server { drive.record.path = draft.remotePath }
            if let account = draft.accountLabel { drive.record.account = account }
            drive.record.name = draft.name.trimmingCharacters(in: .whitespaces)
            drive.record.settings.profile = draft.profile
            drive.record.settings.method = draft.method
            drive.record.settings.timeout = Int(draft.timeout) ?? drive.settings.timeout
            drive.record.settings.mountAtLogin = draft.mountAtLogin
            drive.record.settings.readOnly = draft.readOnly
            drive.record.settings.skipCertificateCheck = draft.skipCertificateCheck
        }
        save()
        await readSpace(drive)
    }

    /// Authorizes again in the browser and remounts with the new token.
    func reconnect(_ drive: Drive) async throws -> String {
        guard let rclone else { throw RcloneError.notFound }
        let (token, account) = try await authorize(drive.provider, client: await storedClient(drive))
        try await rclone.configure(baseRemote(drive), parameters: ["token": token])
        await remount(drive) {
            if let account { drive.record.account = account }
        }
        save()
        return drive.account
    }

    func checkEngineUpdate() async throws -> String {
        guard let rclone else { throw RcloneError.notFound }
        let (current, latest) = try await rclone.updateCheck()
        // The bundled build is named after the release it is built on, with a suffix.
        let release = current.split(separator: "-").first.map(String.init) ?? current
        if latest.isEmpty || latest == release { return "rclone \(release) est à jour" }
        return rclone.isBundled
            ? "rclone \(latest) est sorti, il arrivera avec une prochaine version de Docklume (inclus : \(release))"
            : "rclone \(latest) est disponible (installé : \(current))"
    }

    /// The remote holding the credentials: the wrapped one for an encrypted drive.
    private func baseRemote(_ drive: Drive) -> String {
        drive.record.createdRemotes.first ?? drive.remote
    }

    private func uniqueRemoteName(_ base: String, also taken: [String] = []) -> String {
        let names = Set(remotes.map(\.name) + taken)
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }

    /// A remote name from a drive name: lowercase ASCII, words joined by dashes.
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.isEmpty ? "lecteur" : words.joined(separator: "-")
    }

    // MARK: Polling

    private func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.sampleThroughput()
                if tick % 3 == 0 { self?.syncTags() }
                if tick % 10 == 0 {
                    await self?.measureCaches()
                    await self?.protectDisk()
                }
                // `about` can wait minutes on a slow server, which must not hold the throughput or the disk guard.
                if tick % 300 == 299 { Task { await self?.refreshSpace() } }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Brings the aliases of ~/Cloud/Tags in line with the Finder tags once they or the mounts change, off the main
    /// thread: making an alias reads the item on its drive.
    private func syncTags() {
        guard catalog != nil, !syncingTags else { return }
        let snapshot = drives.map { drive in
            TagShortcuts.Drive(id: drive.id, name: drive.name, mountPoint: drive.mountPoint,
                               cache: MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase), isMounted: drive.isMounted)
        }
        let previous = tagSignature
        syncingTags = true
        Task {
            let signature = await Task.detached(priority: .utility) { () -> String? in
                let signature = TagShortcuts.signature(snapshot)
                guard signature != previous else { return nil }
                TagShortcuts.sync(snapshot)
                return signature
            }.value
            if let signature { tagSignature = signature }
            syncingTags = false
        }
    }

    /// All drives at once, so an rclone that is slow to answer only delays its own figures.
    private func sampleThroughput() async {
        let mounted = drives.compactMap { drive in drive.isMounted ? sessions[drive.id].map { (drive.id, $0) } : nil }
        let samples = await withTaskGroup(of: (Drive.ID, MountSession.Sample?).self) { group in
            for (id, session) in mounted { group.addTask { (id, try? await session.sample()) } }
            var samples: [Drive.ID: MountSession.Sample] = [:]
            for await (id, sample) in group { samples[id] = sample }
            return samples
        }
        for drive in drives {
            if drive.isMounted, let sample = samples[drive.id] {
                drive.readSpeed = sample.read
                drive.writeSpeed = sample.write
                drive.uploads = sample.uploads
                drive.pendingUploads = sample.pending
            } else if !drive.isMounted {
                drive.readSpeed = 0
                drive.writeSpeed = 0
            }
            drive.history.append(drive.isMounted ? drive.readSpeed : 0)
            drive.history.removeFirst(max(0, drive.history.count - 60))
            drive.writeHistory.append(drive.isMounted ? drive.writeSpeed : 0)
            drive.writeHistory.removeFirst(max(0, drive.writeHistory.count - 60))
        }
    }

    /// Unmounted drives also report the files left to upload, which only leave once the drive is mounted again;
    /// their cache is read again only when its size changes. The folders are walked off the main thread, as a cache
    /// can hold many thousands of files.
    private func measureCaches() async {
        let folders = drives.map { ($0.id, MountOptions.cacheDirectory(for: $0, base: preferences.cacheBase)) }
        let sizes = await Task.detached(priority: .utility) { folders.map { ($0.0, DiskSpace.allocated(in: $0.1)) } }.value
        for (id, bytes) in sizes {
            guard let drive = drive(id) else { continue }
            drive.cacheBytes = bytes
            if sessions[id] != nil {
                scannedCaches[id] = nil
            } else if scannedCaches[id] != bytes {
                scannedCaches[id] = bytes
                drive.pendingUploads = await pendingUploadsInBackground(drive).files
            }
        }
    }

    /// `pendingUploads`, reading the description of every file of the cache off the main thread.
    private func pendingUploadsInBackground(_ drive: Drive) async -> CacheFolder.Pending {
        let folder = MountOptions.cacheDirectory(for: drive, base: preferences.cacheBase)
        return await Task.detached(priority: .utility) { CacheFolder.pending(in: folder) }.value
    }

    /// Over NFS rclone cannot evict a file while it is being read, so a long stream outgrows the cache quota.
    /// When the disk gets close to full, the drive with the most cache to free is remounted with only its files
    /// still waiting to be uploaded, which nothing may delete.
    private func protectDisk() async {
        guard let free = DiskSpace.available(at: FileManager.default.homeDirectoryForCurrentUser), free < DiskSpace.floor else { return }
        // A drive with files waiting is left alone: remounting it would break the copy writing them, and rclone
        // removes what it has sent itself, holding writes until there is room. rclone marks a file as waiting from
        // its first write, before it counts it as an upload.
        var candidates: [(drive: Drive, freeable: Int64)] = []
        var waiting = false
        for drive in drives where drive.isMounted {
            if await pendingUploadsInBackground(drive).files > 0 {
                waiting = true
            } else {
                candidates.append((drive, drive.cacheBytes))
            }
        }
        guard let (drive, freeable) = candidates.max(by: { $0.freeable < $1.freeable }), freeable >= 1_000_000_000 else {
            if !warnedDiskFull, waiting {
                warnedDiskFull = true
                notify("Le disque est presque plein", "Des fichiers attendent d'être envoyés et ne peuvent pas être retirés du cache. Libérez de la place sur ce Mac.")
            }
            return
        }
        warnedDiskFull = false
        await clearCache(drive)
        drive.notice = "Cache vidé (\(Format.gigabytes(freeable))) et lecteur remonté : le disque était presque plein."
    }

    private func warnIfNearlyFull(_ drive: Drive) {
        guard SpaceLevel(drive.space).isNearlyFull, preferences.notifyNearlyFull, !warnedFull.contains(drive.id),
              let free = SpaceLevel(drive.space).free else { return }
        warnedFull.insert(drive.id)
        notify("« \(drive.name) » est presque plein", "Il reste \(Format.capacity(free)) libres.")
    }

    private func notify(_ title: String, _ body: String) {
        guard catalog != nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
