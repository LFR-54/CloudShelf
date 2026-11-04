import Foundation

/// One rclone mount process serving one drive, with its own rc server for live stats.
@MainActor
final class MountSession {
    let mountPoint: URL
    /// Where this run starts in the log, which keeps the lines of earlier runs.
    let logOffset: UInt64
    /// Called once, when rclone has exited or Docklume has given up on it, with the exit status when known.
    var onExit: ((Int32?) -> Void)?

    /// The process Docklume started; nil for one taken over from a previous run, whose status cannot be known.
    private let process: Process?
    private var pid: pid_t = 0
    private var exitSource: DispatchSourceProcess?
    private let usesFUSE: Bool
    private let control: RemoteControl
    private var lastSample: (bytes: Int64, received: Int64?, time: ContinuousClock.Instant)?
    private var uploads: [String: Int64] = [:]

    /// `command` is `nfsmount`, or `mount` for macFUSE.
    init(rclone: Rclone, command: String, remote: String, volumeName: String, mountPoint: URL, options: [String], logFile: URL) throws {
        self.mountPoint = mountPoint
        logOffset = RcloneLog.size(of: logFile)
        usesFUSE = command == "mount"
        control = try RemoteControl()
        let process = Process()
        process.executableURL = rclone.executable
        process.arguments = [command, remote, mountPoint.path,
                             "--volname", volumeName,
                             "--rc", "--rc-addr", control.address,
                             "--log-file", logFile.path, "--log-level", "INFO"] + options
        process.environment = ProcessInfo.processInfo.environment.merging(control.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.finish(status) }
        }
        try process.run()
        pid = process.processIdentifier
    }

    /// Takes over an rclone mount that a previous run of Docklume left running.
    init(adopting orphan: OrphanMount, logFile: URL) {
        mountPoint = orphan.mountPoint
        logOffset = RcloneLog.size(of: logFile)
        usesFUSE = orphan.command == "mount"
        control = RemoteControl(port: orphan.port, user: orphan.user, password: orphan.password)
        process = nil
        pid = orphan.pid
        let source = DispatchSource.makeProcessSource(identifier: orphan.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        source.resume()
        exitSource = source
        // An exit before the source was watching would never be reported.
        if !isRunning { Task { @MainActor [weak self] in self?.finish(nil) } }
    }

    var isRunning: Bool { process?.isRunning ?? (kill(pid, 0) == 0) }

    private func finish(_ status: Int32?) {
        exitSource?.cancel()
        exitSource = nil
        guard let onExit else { return }
        self.onExit = nil
        onExit(status)
    }

    /// Reports the end without waiting for rclone, for a process stuck in the kernel as it exits.
    func abandon() { finish(nil) }

    private func signal(_ signal: Int32) {
        if isRunning { kill(pid, signal) }
    }

    /// Asks rclone to unmount and exit.
    ///
    /// A macFUSE volume is unmounted from the system side, after which rclone exits by itself; a file still open
    /// keeps the volume busy, so the unmount is then forced. On a signal, rclone forces the unmount from inside its
    /// own process, which can leave that process, and the one holding the file, stuck in the kernel for minutes.
    /// The signal remains for a volume that refuses to unmount.
    func stop() {
        guard isRunning else { return }
        guard usesFUSE else { return signal(SIGINT) }
        Task {
            if await !Mounts.unmount(mountPoint), await !Mounts.unmount(mountPoint, force: true) { signal(SIGINT) }
        }
    }

    /// Unmounts from the system side when rclone does not answer, then ends the process.
    func forceStop() async {
        await Mounts.unmount(mountPoint, force: true)
        signal(SIGTERM)
    }

    func call(_ method: String, _ parameters: [String: String] = [:]) async throws {
        try await control.call(method, parameters)
    }

    struct Sample: Sendable {
        let read: Double
        let write: Double
        let uploads: [Upload]
        let pending: Int
    }

    /// Read and write throughput in bytes per second since the previous sample, and the uploads in progress.
    ///
    /// Reads are what the bundled rclone downloads, read ahead included, as the network carries it. core/stats only
    /// counts data once the reading app takes it, which macFUSE does in bursts of hundreds of megabytes.
    func sample() async throws -> Sample {
        async let core = control.call("core/stats", as: CoreStats.self)
        async let downloaded = try? control.call("core/downloaded", as: Downloaded.self)
        async let vfs = try? control.call("vfs/stats", as: VFSStats.self)
        let stats = try await core
        let received = await downloaded?.bytes
        let cache = await vfs?.diskCache
        let pending = (cache?.uploadsInProgress ?? 0) + (cache?.uploadsQueued ?? 0)
        let now = ContinuousClock.now
        let sending = (stats.transferring ?? []).filter { $0.dstFs != nil }
        let current = Dictionary(sending.map { ($0.name, $0.bytes) }, uniquingKeysWith: max)
        let written = current.reduce(Int64(0)) { sum, upload in sum + max(0, upload.value - (uploads[upload.key] ?? 0)) }
        let list = sending.map { Upload(name: $0.name, bytes: $0.bytes, size: $0.size ?? 0, speed: $0.speed ?? 0) }
        defer {
            lastSample = (stats.bytes, received, now)
            uploads = current
        }
        guard let last = lastSample else { return Sample(read: 0, write: 0, uploads: list, pending: pending) }
        let seconds = (now - last.time) / .seconds(1)
        guard seconds > 0 else { return Sample(read: 0, write: 0, uploads: list, pending: pending) }
        let total = Double(max(0, stats.bytes - last.bytes))
        let write = min(total, Double(written))
        let read = if let received, let before = last.received { Double(max(0, received - before)) } else { total - write }
        return Sample(read: read / seconds, write: write / seconds, uploads: list, pending: pending)
    }
}

/// An rclone mount still running after the Docklume that started it quit without stopping it, found by its
/// command line and environment, which carry the address and password of its rc server.
struct OrphanMount: Sendable {
    let pid: pid_t
    /// `mount` or `nfsmount`.
    let command: String
    let mountPoint: URL
    let cacheDirectory: String
    let port: Int
    let user: String
    let password: String

    /// The orphaned rclone mounts of this user; their parent is launchd once Docklume has gone.
    static func all() -> [OrphanMount] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        return pids.prefix(Int(max(0, filled))).compactMap(OrphanMount.init(pid:))
    }

    private init?(pid: pid_t) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_ppid == 1, info.pbi_uid == getuid(),
              let (arguments, environment) = Self.commandLine(of: pid), arguments.count > 3,
              URL(filePath: arguments[0]).lastPathComponent == "rclone", ["mount", "nfsmount"].contains(arguments[1]) else { return nil }
        func flag(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        func variable(_ name: String) -> String? {
            environment.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
        }
        guard let cache = flag("--cache-dir"), let address = flag("--rc-addr"),
              let port = address.split(separator: ":").last.flatMap({ Int($0) }),
              let user = variable("RCLONE_RC_USER"), let password = variable("RCLONE_RC_PASS") else { return nil }
        self.pid = pid
        command = arguments[1]
        mountPoint = URL(filePath: arguments[3], directoryHint: .isDirectory)
        cacheDirectory = cache
        self.port = port
        self.user = user
        self.password = password
    }

    /// The arguments and environment a process started with: KERN_PROCARGS2 holds argc, the executable path,
    /// padding, then the NUL-terminated arguments followed by the environment.
    private static func commandLine(of pid: pid_t) -> (arguments: [String], environment: [String])? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var strings: [String] = [], index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        while index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            if index == start { break }
            strings.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        guard strings.count >= argc else { return nil }
        return (Array(strings.prefix(argc)), Array(strings.dropFirst(argc)))
    }
}

enum Mounts {
    /// Reads the kernel mount table without touching the file system, so a stalled mount cannot block.
    static func isMounted(_ url: URL) -> Bool {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return false }
        var table: [statfs] = Array(repeating: .init(), count: Int(count))
        let filled = table.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32($0.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        return table.prefix(Int(max(0, filled))).contains { entry in
            let mountedOn = withUnsafeBytes(of: entry.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return same(URL(filePath: mountedOn), url)
        }
    }

    /// Whether two paths name the same mount point. The mount table keeps the on-disk case (~/cloud for ~/Cloud) and
    /// resolved symbolic links (/private/tmp for /tmp); links are resolved in the parent folder only, as the volume
    /// itself may not answer.
    static func same(_ first: URL, _ second: URL) -> Bool {
        tablePath(first).compare(tablePath(second), options: .caseInsensitive) == .orderedSame
    }

    private static func tablePath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false).trimmingSuffix("/")
        let parent = (path as NSString).deletingLastPathComponent
        guard let resolved = realpath(parent, nil) else { return path }
        defer { free(resolved) }
        return (String(cString: resolved) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
    }

    /// `umount`, awaited without blocking: a dead NFS server can take seconds to answer. Without `force`, it fails
    /// while a file on the volume is open. Returns whether the volume was unmounted.
    @discardableResult
    static func unmount(_ url: URL, force: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            let umount = Process()
            umount.executableURL = URL(filePath: "/sbin/umount")
            umount.arguments = (force ? ["-f"] : []) + [url.path]
            umount.standardError = FileHandle.nullDevice
            umount.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try umount.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
