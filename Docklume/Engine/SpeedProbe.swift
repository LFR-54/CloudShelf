import Foundation

/// Reads a stretch of a real file and times it, for the speed test of the drive page.
enum SpeedProbe {
    struct Result: Sendable {
        let speed: Double
        /// Time to the first byte, in milliseconds.
        let latency: Int
    }

    /// Through the mount, so the test covers the path the Finder and media servers use.
    static func readFile(at url: URL, offset: Int64, length: Int64, progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        try await measure(progress: progress) {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.seek(toOffset: UInt64(offset))
            return (handle, length, {})
        }
    }

    /// Straight from rclone when the drive is not mounted.
    static func readRemote(_ rclone: Rclone, path: String, offset: Int64, length: Int64,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        try await measure(progress: progress) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = rclone.executable
            process.arguments = ["cat", path, "--offset", "\(offset)", "--count", "\(length)"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            return (pipe.fileHandleForReading, length, { if process.isRunning { process.terminate() } })
        }
    }

    private static func measure(progress: @escaping @Sendable (Double) -> Void,
                                open: @escaping @Sendable () throws -> (FileHandle, Int64, () -> Void)) async throws -> Result {
        let cancelled = Flag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let (handle, length, finish) = try open()
                defer { finish(); try? handle.close() }
                let start = ContinuousClock.now
                var first: Duration?
                var total: Int64 = 0, reported: Int64 = 0
                while total < length, !cancelled.isSet, let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                    if first == nil { first = ContinuousClock.now - start }
                    total += Int64(chunk.count)
                    if total - reported >= 32 << 20 {
                        reported = total
                        progress(Double(total) / Double(length))
                    }
                }
                if cancelled.isSet { throw CancellationError() }
                let seconds = (ContinuousClock.now - start) / .seconds(1)
                guard total > 0, seconds > 0 else { throw RcloneError.command("Aucune donnée n'a été lue.") }
                return Result(speed: Double(total) / seconds, latency: Int(((first ?? .zero) / .milliseconds(1)).rounded()))
            }.value
        } onCancel: {
            cancelled.set()
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }
}
