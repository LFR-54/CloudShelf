import Foundation

/// One rclone mount process serving one drive, with its own rc server for live stats.
@MainActor
final class MountSession {
    let mountPoint: URL
    var onExit: ((Int32) -> Void)?

    private let process = Process()
    private let control: RemoteControl
    private var lastSample: (bytes: Int64, received: Int64?, time: ContinuousClock.Instant)?
    private var uploads: [String: Int64] = [:]

    /// `command` is `nfsmount`, or `mount` for macFUSE.
    init(rclone: Rclone, command: String, remote: String, volumeName: String, mountPoint: URL, options: [String], logFile: URL) throws {
        self.mountPoint = mountPoint
        control = try RemoteControl()
        process.executableURL = rclone.executable
        process.arguments = [command, remote, mountPoint.path,
                             "--volname", volumeName,
                             "--rc", "--rc-addr", control.address,
                             "--log-file", logFile.path, "--log-level", "INFO"] + options
        process.environment = ProcessInfo.processInfo.environment.merging(control.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.onExit?(status) }
        }
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    /// Asks rclone to unmount and exit.
    func stop() {
        if process.isRunning { process.interrupt() }
    }

    /// Unmounts from the system side when rclone does not answer, then ends the process.
    func forceStop() async {
        await Mounts.forceUnmount(mountPoint)
        if process.isRunning { process.terminate() }
    }

    func call(_ method: String, _ parameters: [String: String] = [:]) async throws {
        try await control.call(method, parameters)
    }

    /// Read and write throughput in bytes per second since the previous sample, and the uploads in progress.
    ///
    /// Reads are what the bundled rclone downloads, read ahead included, as the network carries it. core/stats only
    /// counts data once the reading app takes it, which macFUSE does in bursts of hundreds of megabytes.
    func sample() async throws -> (read: Double, write: Double, uploads: [Upload], pending: Int) {
        let stats = try await control.call("core/stats", as: CoreStats.self)
        let received = try? await control.call("core/downloaded", as: Downloaded.self).bytes
        let cache = (try? await control.call("vfs/stats", as: VFSStats.self))?.diskCache
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
        guard let last = lastSample else { return (0, 0, list, pending) }
        let seconds = (now - last.time) / .seconds(1)
        guard seconds > 0 else { return (0, 0, list, pending) }
        let total = Double(max(0, stats.bytes - last.bytes))
        let write = min(total, Double(written))
        let read = if let received, let before = last.received { Double(max(0, received - before)) } else { total - write }
        return (read / seconds, write / seconds, list, pending)
    }
}

enum Mounts {
    /// Reads the kernel mount table without touching the file system, so a stalled mount cannot block.
    /// The table keeps the on-disk case (~/cloud for ~/Cloud), hence the case-insensitive match.
    static func isMounted(_ url: URL) -> Bool {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return false }
        var table: [statfs] = Array(repeating: .init(), count: Int(count))
        let filled = table.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32($0.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        let path = url.path(percentEncoded: false).trimmingSuffix("/")
        return table.prefix(Int(max(0, filled))).contains { entry in
            let mountedOn = withUnsafeBytes(of: entry.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return mountedOn.compare(path, options: .caseInsensitive) == .orderedSame
        }
    }

    /// `umount -f`, awaited without blocking: a dead NFS server can take seconds to answer.
    static func forceUnmount(_ url: URL) async {
        await withCheckedContinuation { continuation in
            let umount = Process()
            umount.executableURL = URL(filePath: "/sbin/umount")
            umount.arguments = ["-f", url.path]
            umount.standardError = FileHandle.nullDevice
            umount.terminationHandler = { _ in continuation.resume() }
            do {
                try umount.run()
            } catch {
                continuation.resume()
            }
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
