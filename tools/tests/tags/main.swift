import Foundation

// An alias that CloudShelf made, in a fake Tags folder: sync keeps it and marks it as Docklume's.
let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory).appending(path: "Tags", directoryHint: .isDirectory)
let alias = root.appending(path: "Vert/Projet")
try! FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
try! Data("alias".utf8).write(to: alias)
let target = Data("DRIVE\n/Users/x/Cloud/Google Drive\n/Projet".utf8)
_ = target.withUnsafeBytes { setxattr(alias.path, "fr.cloudshelf.target", $0.baseAddress, target.count, 0, XATTR_NOFOLLOW) }

@MainActor func attr(_ name: String) -> String? {
    let size = getxattr(alias.path, name, nil, 0, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { return nil }
    var data = Data(count: size)
    _ = data.withUnsafeMutableBytes { getxattr(alias.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
    return String(decoding: data, as: UTF8.self)
}

var failures = 0
@MainActor func check(_ label: String, _ ok: Bool) { print(ok ? "ok    \(label)" : "ÉCHEC \(label)"); if !ok { failures += 1 } }

let drive = TagShortcuts.Drive(id: "DRIVE", name: "Google Drive", mountPoint: URL(filePath: "/Users/x/Cloud/Google Drive"),
                               cache: URL(filePath: CommandLine.arguments[1]).appending(path: "cache"), isMounted: false)
TagShortcuts.sync([drive], root: root)
check("alias gardé", FileManager.default.fileExists(atPath: alias.path))
check("marqué comme alias de Docklume", attr("fr.docklume.target") == String(decoding: target, as: UTF8.self))
check("ancienne marque retirée", attr("fr.cloudshelf.target") == nil)
exit(failures == 0 ? 0 : 1)
