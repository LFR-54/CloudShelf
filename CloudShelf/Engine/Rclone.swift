import Foundation

/// The rclone binary and its one-shot commands.
struct Rclone: Sendable {
    let executable: URL

    /// The bundled binary first, then the usual install locations.
    static func locate() -> Rclone? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            Bundle.main.url(forAuxiliaryExecutable: "rclone"),
            home.appending(path: ".local/bin/rclone"),
            URL(filePath: "/opt/homebrew/bin/rclone"),
            URL(filePath: "/usr/local/bin/rclone")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }.map(Rclone.init)
    }

    var isBundled: Bool { executable.path.hasPrefix(Bundle.main.bundlePath) }

    func version() async throws -> String {
        let output = try await run(["version"])
        let firstLine = output.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.replacingOccurrences(of: "rclone v", with: "")
    }

    func remotes() async throws -> [Remote] {
        try JSONDecoder().decode([Remote].self, from: Data(try await run(["listremotes", "--json"]).utf8))
    }

    func about(_ remote: String, config: URL? = nil) async throws -> Space {
        try JSONDecoder().decode(Space.self, from: Data(try await run(["about", remote, "--json"], config: config).utf8))
    }

    /// Every remote with its parameters; secrets included, so the result stays in memory.
    func dump(config: URL? = nil) async throws -> [String: [String: String]] {
        let output = try await run(["config", "dump"], config: config)
        let raw = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: [String: Any]] ?? [:]
        return raw.mapValues { $0.compactMapValues { "\($0)" } }
    }

    func configFile() async throws -> String {
        try await run(["config", "file"]).split(separator: "\n").last.map(String.init) ?? ""
    }

    /// Creates or updates a remote without prompts, answering rclone's follow-up questions with their defaults.
    func configure(_ name: String, type: String? = nil, parameters: [String: String], config: URL? = nil) async throws {
        let assignments = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var arguments = ["config", type == nil ? "update" : "create", name] + (type.map { [$0] } ?? []) + assignments + ["--non-interactive"]
        for _ in 0..<12 {
            let step = try JSONDecoder().decode(ConfigStep.self, from: Data(try await run(arguments, config: config).utf8))
            if !step.error.isEmpty { throw RcloneError.command(step.error) }
            guard !step.state.isEmpty else { return }
            // Keep the token just obtained; take rclone's default for anything else.
            let answer = step.option?.name == "config_refresh_token" ? "false" : step.option?.defaultString ?? ""
            arguments = ["config", "update", name, "--continue", "--state", step.state, "--result", answer, "--non-interactive"]
        }
        throw RcloneError.command("La configuration de rclone n'a pas abouti.")
    }

    func deleteRemote(_ name: String) async throws {
        _ = try await run(["config", "delete", name])
    }

    /// Opens the browser to authorize an OAuth backend and returns the token JSON; without a client, with rclone's own key.
    func authorize(_ type: String, client: OAuthClient? = nil) async throws -> String {
        let output = try await run(["authorize", type] + (client.map { [$0.id, $0.secret] } ?? []))
        guard let start = output.range(of: "--->"), let end = output.range(of: "<---End paste") else {
            throw RcloneError.command("L'autorisation n'a pas renvoyé de jeton.")
        }
        return output[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first file of at least `minimum` bytes, searched four levels deep.
    func firstFile(in remote: String, minimum: Int64) async throws -> (path: String, size: Int64)? {
        let line = try await firstLine(["lsf", remote, "-R", "--files-only", "--min-size", "\(minimum)B", "--max-depth", "4", "--format", "sp", "--separator", "\t"])
        guard let line, let tab = line.firstIndex(of: "\t"), let size = Int64(line[..<tab]) else { return nil }
        return (String(line[line.index(after: tab)...]), size)
    }

    /// The installed and latest stable versions.
    func updateCheck() async throws -> (current: String, latest: String) {
        let output = try await run(["selfupdate", "--check"])
        func value(_ key: String) -> String {
            output.split(separator: "\n").first { $0.hasPrefix(key) }
                .map { $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? "" } ?? ""
        }
        return (value("yours:"), value("latest:"))
    }

    /// Runs rclone off the cooperative pool and returns its standard output; cancelling the task ends the process.
    func run(_ arguments: [String], config: URL? = nil) async throws -> String {
        let box = ProcessBox()
        box.process.executableURL = executable
        box.process.arguments = arguments + (config.map { ["--config", $0.path] } ?? [])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = box.process
                    let output = Pipe(), errors = Pipe()
                    process.standardOutput = output
                    process.standardError = errors
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    let out = output.fileHandleForReading.readDataToEndOfFile()
                    let err = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: String(decoding: out, as: UTF8.self))
                    } else if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: RcloneError.command(RcloneLog.lastMessage(in: String(decoding: err, as: UTF8.self))))
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Reads the first line of a listing and stops rclone there.
    private func firstLine(_ arguments: [String]) async throws -> String? {
        let box = ProcessBox()
        box.process.executableURL = executable
        box.process.arguments = arguments
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = box.process
                    let output = Pipe()
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    var buffer = Data()
                    while !buffer.contains(0x0A) {
                        let chunk = output.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        buffer.append(chunk)
                    }
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    let line = String(decoding: buffer, as: UTF8.self).split(separator: "\n").first.map(String.init)
                    continuation.resume(returning: line)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

/// Lets a cancellation handler end a process started on another thread.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

private struct ConfigStep: Decodable {
    struct Option: Decodable {
        let name: String
        let defaultString: String

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case defaultString = "DefaultStr"
        }
    }

    let state: String
    let option: Option?
    let error: String

    enum CodingKeys: String, CodingKey {
        case state = "State"
        case option = "Option"
        case error = "Error"
    }
}

struct Remote: Decodable, Sendable, Equatable {
    let name: String
    let type: String
}

struct Space: Decodable, Sendable, Equatable {
    let total: Int64?
    let used: Int64?
    let free: Int64?
}

enum RcloneError: LocalizedError {
    case notFound
    case command(String?)

    var errorDescription: String? {
        switch self {
        case .notFound: "rclone est introuvable. Installez-le dans ~/.local/bin ou avec Homebrew."
        case .command(let message): message ?? "rclone a échoué."
        }
    }
}

enum RcloneLog {
    /// The message of the last line, without rclone's date and level prefix.
    static func lastMessage(in text: String, levels: [String] = ["CRITICAL", "ERROR", "Failed"]) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        guard let line = lines.last(where: { line in levels.contains { line.contains($0) } }) ?? lines.last else { return nil }
        let message = line.replacing(#/^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} [A-Z]+\s*: /#, with: "")
        return message.isEmpty ? nil : message
    }

    /// Errors that say nothing to someone who does not know rclone. 202264815644 is the Google Cloud project behind
    /// rclone's shared Google Drive key.
    static func explain(_ message: String) -> String {
        guard message.contains("Quota exceeded") || message.contains("rateLimitExceeded") else { return message }
        return message.contains("202264815644")
            ? "Google refuse les requêtes : la clé partagée de rclone a dépassé son quota. Réessayez plus tard, ou utilisez votre propre clé dans la fiche du lecteur."
            : "Google refuse les requêtes : quota dépassé. Réessayez dans quelques minutes."
    }

    /// The last error written to a log file, reading only its tail.
    static func lastError(at url: URL) -> String? {
        let tail = tail(of: url, bytes: 16_384)
        guard tail.contains("ERROR") || tail.contains("CRITICAL") else { return nil }
        return lastMessage(in: tail)
    }

    static func tail(of url: URL, bytes: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        // Drop the first, probably partial, line.
        return size > bytes ? String(text.drop { $0 != "\n" }.dropFirst()) : text
    }

    struct Line: Identifiable, Hashable {
        let id: Int
        let time: String
        let level: String
        let message: String
    }

    /// The lines of a log file: time, level and message.
    static func lines(at url: URL, limit: Int = 600) -> [Line] {
        let pattern = #/^\d{4}/\d{2}/\d{2} (\d{2}:\d{2}:\d{2}) ([A-Z]+)\s*: ?(.*)$/#
        let parsed = tail(of: url, bytes: 400_000).split(separator: "\n").compactMap { line -> (String, String, String)? in
            guard let match = try? pattern.wholeMatch(in: String(line)) else { return nil }
            return (String(match.1), String(match.2), String(match.3))
        }
        return parsed.suffix(limit).enumerated().map { Line(id: $0.offset, time: $0.element.0, level: $0.element.1, message: $0.element.2) }
    }
}
