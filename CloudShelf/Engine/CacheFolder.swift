import Foundation

/// A drive's rclone cache folder, changed only while its rclone is stopped.
///
/// A file written to a drive lives only here until rclone has uploaded it: its data under vfs/ and, under
/// vfsMeta/, a JSON description whose "Dirty" stays true until the upload succeeds. rclone uploads such files
/// again at the next mount, so they must survive every clean-up.
enum CacheFolder {
    struct Pending: Sendable {
        var files = 0
        var bytes: Int64 = 0
    }

    /// The files waiting to be uploaded. A description that cannot be read counts as waiting.
    static func pending(in folder: URL) -> Pending {
        var pending = Pending()
        for (_, size) in dirty(in: folder) {
            pending.files += 1
            pending.bytes += size
        }
        return pending
    }

    /// The Finder tags of the drive's files, which the bundled rclone keeps here (rclone-patches): the remote has
    /// nowhere to keep them, so they exist only in this folder.
    static let finderTags = "finderMeta"

    /// Deletes everything but the files waiting to be uploaded, which it returns, and the Finder tags.
    @discardableResult
    static func purge(_ folder: URL) -> Pending {
        let manager = FileManager.default
        let keep = dirty(in: folder)
        for item in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = item.lastPathComponent
            if name != finderTags, keep.isEmpty || !["vfs", "vfsMeta"].contains(name) { try? manager.removeItem(at: item) }
        }
        if !keep.isEmpty {
            for root in ["vfs", "vfsMeta"] {
                for file in files(under: folder.appending(path: root)) where keep[file.relative] == nil {
                    try? manager.removeItem(at: file.url)
                }
            }
        }
        removeEmptyFolders(in: folder)
        if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? manager.removeItem(at: folder) }
        return keep.values.reduce(into: Pending()) { pending, size in
            pending.files += 1
            pending.bytes += size
        }
    }

    /// Moves the files waiting to be uploaded and the Finder tags to another cache folder, replacing older copies
    /// there, and deletes the rest.
    static func move(_ folder: URL, to destination: URL) {
        purge(folder)
        let manager = FileManager.default
        for root in ["vfs", "vfsMeta", finderTags] {
            for file in files(under: folder.appending(path: root)) {
                let target = destination.appending(path: root).appending(path: file.relative)
                try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? manager.removeItem(at: target)
                try? manager.moveItem(at: file.url, to: target)
            }
        }
        removeEmptyFolders(in: folder)
        try? manager.removeItem(at: folder)
    }

    private struct Description: Decodable {
        let dirty: Bool
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case dirty = "Dirty", size = "Size"
        }
    }

    /// Paths below vfsMeta of the files waiting to be uploaded, with their sizes.
    private static func dirty(in folder: URL) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for file in files(under: folder.appending(path: "vfsMeta")) {
            let description = (try? Data(contentsOf: file.url)).flatMap { try? JSONDecoder().decode(Description.self, from: $0) }
            if description?.dirty ?? true { result[file.relative] = description?.size ?? 0 }
        }
        return result
    }

    /// The regular files below a folder, with their paths relative to it.
    private static func files(under root: URL) -> [(url: URL, relative: String)] {
        let base = root.resolvingSymlinksInPath().pathComponents
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return items.compactMap { item in
            guard let url = item as? URL, (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
            let components = url.resolvingSymlinksInPath().pathComponents
            guard components.starts(with: base) else { return nil }
            return (url, components.dropFirst(base.count).joined(separator: "/"))
        }
    }

    /// Deepest first, so a parent is empty by the time it is reached.
    private static func removeEmptyFolders(in folder: URL) {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let folders = items.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        for url in folders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true { try? FileManager.default.removeItem(at: url) }
        }
    }
}
