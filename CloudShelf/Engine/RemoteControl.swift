import Foundation

/// Client for the rc API of one rclone process, bound to 127.0.0.1 with a per-launch password.
struct RemoteControl: Sendable {
    let port: Int
    let user = "cloudshelf"
    let password = UUID().uuidString

    init() throws {
        port = try Self.freePort()
    }

    var address: String { "127.0.0.1:\(port)" }

    /// Credentials go through the environment so they never show in the process list.
    var environment: [String: String] { ["RCLONE_RC_USER": user, "RCLONE_RC_PASS": password] }

    func call<Result: Decodable & Sendable>(_ method: String, _ parameters: [String: String] = [:], as type: Result.Type) async throws -> Result {
        var request = URLRequest(url: URL(string: "http://\(address)/\(method)")!, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Result.self, from: data)
    }

    func call(_ method: String, _ parameters: [String: String] = [:]) async throws {
        _ = try await call(method, parameters, as: Ignored.self)
    }

    private struct Ignored: Decodable, Sendable {}

    private static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        guard result else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

struct CoreStats: Decodable, Sendable {
    struct Transfer: Decodable, Sendable {
        let name: String
        let bytes: Int64
        let size: Int64?
        let speed: Double?
        let dstFs: String?
    }

    let bytes: Int64
    let transferring: [Transfer]?
}

/// The VFS cache of vfs/stats; absent when the drive has no cache.
struct VFSStats: Decodable, Sendable {
    struct Cache: Decodable, Sendable {
        let uploadsInProgress: Int
        let uploadsQueued: Int
    }

    let diskCache: Cache?
}

/// Bytes received by the bundled rclone's parallel readers (rclone-patches).
struct Downloaded: Decodable, Sendable {
    let bytes: Int64
}
