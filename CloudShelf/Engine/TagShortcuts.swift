import Foundation

/// Finder aliases to the tagged items of the drives, gathered in ~/Cloud/Tags with one folder per tag.
///
/// The Finder lists the items of a tag through Spotlight, which does not index macFUSE volumes: the tags the
/// bundled rclone keeps (CacheFolder.finderTags) show on the items but not under Tags in the sidebar. An alias on
/// this disk shows there once Spotlight indexes it, bearing the tag of its folder, and the folders can be pinned
/// in the sidebar. CloudShelf marks the aliases it makes and only ever removes those.
enum TagShortcuts {
    struct Drive: Sendable {
        let id: String
        let name: String
        let mountPoint: URL
        let cache: URL
        let isMounted: Bool
    }

    static let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Cloud/Tags", directoryHint: .isDirectory)

    /// The drive, mount point and path an alias leads to, one per line.
    private static let targetAttribute = "fr.cloudshelf.target"
    private static let tagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    private struct Key: Hashable {
        let drive: String
        let mountPoint: String
        let path: String
        /// The tag's folder name.
        let tag: String
    }

    /// The tag files of the drives, by date, and which drives are mounted: a sync is due when this changes.
    static func signature(_ drives: [Drive]) -> String {
        drives.map { drive in
            let files = tagFiles(in: drive.cache).map { "\($0.lastPathComponent)@\(modified($0))" }
            return "\(drive.id):\(drive.mountPoint.path):\(drive.isMounted):\(files.joined(separator: ","))"
        }.joined(separator: "|")
    }

    /// Makes the aliases match the tags of the mounted drives. Those of a drive not mounted stay until it is, as
    /// its tags cannot be checked, and those of a deleted drive go.
    static func sync(_ drives: [Drive], root: URL = root) {
        var wanted: [Key: Data] = [:]
        for drive in drives where drive.isMounted {
            for (path, tags) in taggedItems(in: drive.cache) {
                for (tag, value) in tags {
                    wanted[Key(drive: drive.id, mountPoint: drive.mountPoint.path, path: path, tag: tag)] = value
                }
            }
        }
        let byID = Dictionary(drives.map { ($0.id, $0) }) { first, _ in first }
        var kept: Set<Key> = []
        for (url, key) in aliases(in: root) {
            guard let drive = byID[key.drive], !drive.isMounted || wanted[key] != nil else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            kept.insert(key)
            if let value = wanted[key], attribute(tagsAttribute, of: url) != value { setAttribute(tagsAttribute, value, on: url) }
        }
        for (key, value) in wanted where !kept.contains(key) {
            guard let drive = byID[key.drive] else { continue }
            create(key, tags: value, drive: drive, root: root)
        }
        removeEmptyFolders(in: root)
    }

    /// The tags of each item of a drive, by tag folder name, each with the attribute an alias in that folder bears:
    /// that one tag alone, so the Finder lists every item once under each of its tags.
    private static func taggedItems(in cache: URL) -> [String: [String: Data]] {
        var items: [String: [String: Data]] = [:]
        for file in tagFiles(in: cache) {
            guard let data = try? Data(contentsOf: file),
                  let attributes = try? JSONDecoder().decode([String: [String: Data]].self, from: data) else { continue }
            for (path, values) in attributes where path != "/" {
                guard let value = values[tagsAttribute],
                      let tags = try? PropertyListSerialization.propertyList(from: value, format: nil) as? [String] else { continue }
                var byFolder: [String: Data] = [:]
                for tag in tags {
                    let name = tag.components(separatedBy: "\n")[0].replacingOccurrences(of: "/", with: "-")
                    guard !name.isEmpty, !name.hasPrefix("."),
                          let single = try? PropertyListSerialization.data(fromPropertyList: [tag], format: .binary, options: 0) else { continue }
                    byFolder[name] = single
                }
                items[path] = byFolder
            }
        }
        return items
    }

    private static func tagFiles(in cache: URL) -> [URL] {
        let folder = cache.appending(path: CacheFolder.finderTags, directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func modified(_ url: URL) -> TimeInterval {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast).timeIntervalSince1970
    }

    /// The aliases CloudShelf made, with where they lead.
    private static func aliases(in root: URL) -> [(URL, Key)] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders.flatMap { folder -> [(URL, Key)] in
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { url in
                guard let value = attribute(targetAttribute, of: url) else { return nil }
                let lines = String(decoding: value, as: UTF8.self).components(separatedBy: "\n")
                guard lines.count == 3 else { return nil }
                return (url, Key(drive: lines[0], mountPoint: lines[1], path: lines[2], tag: folder.lastPathComponent))
            }
        }
    }

    /// An alias needs its item to exist, so it is made only while the drive is mounted.
    private static func create(_ key: Key, tags: Data, drive: Drive, root: URL) {
        let target = drive.mountPoint.appending(path: String(key.path.drop { $0 == "/" }))
        guard let bookmark = try? target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let folder = root.appending(path: key.tag, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let parent = (key.path as NSString).deletingLastPathComponent
        let alias = freeName(in: folder, for: target.lastPathComponent, from: parent == "/" ? drive.name : (parent as NSString).lastPathComponent)
        guard (try? URL.writeBookmarkData(bookmark, to: alias)) != nil else { return }
        setAttribute(targetAttribute, Data("\(key.drive)\n\(key.mountPoint)\n\(key.path)".utf8), on: alias)
        setAttribute(tagsAttribute, tags, on: alias)
    }

    /// The item's name, followed by its folder's, or its drive's at the top, when another item of that name has the tag.
    private static func freeName(in folder: URL, for name: String, from place: String) -> URL {
        let manager = FileManager.default
        let first = folder.appending(path: name)
        guard manager.fileExists(atPath: first.path) else { return first }
        var number = 1
        while true {
            let candidate = folder.appending(path: number == 1 ? "\(name) (\(place))" : "\(name) (\(place)) \(number)")
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    /// The folder of a tag goes with its last alias; the root stays, as it may be pinned in the sidebar.
    private static func removeEmptyFolders(in root: URL) {
        let manager = FileManager.default
        for folder in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let contents = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? ["?"]
            if contents.allSatisfy({ $0 == ".DS_Store" }) { try? manager.removeItem(at: folder) }
        }
    }

    private static func attribute(_ name: String, of url: URL) -> Data? {
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read == size ? data : nil
    }

    private static func setAttribute(_ name: String, _ value: Data, on url: URL) {
        _ = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
    }
}
