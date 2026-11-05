import Foundation

// Runs FormerName.migrate on a fake home folder and checks what moved. Prints one line per check.
let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let fm = FileManager.default
var failures = 0
@MainActor func check(_ label: String, _ ok: Bool) { print(ok ? "ok    \(label)" : "ÉCHEC \(label)"); if !ok { failures += 1 } }
@MainActor func write(_ path: String, _ text: String, in home: URL) {
    let url = home.appending(path: path); try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: url)
}
@MainActor func read(_ path: String, in home: URL) -> String? { (try? Data(contentsOf: home.appending(path: path))).map { String(decoding: $0, as: UTF8.self) } }
@MainActor func suite(_ name: String) -> UserDefaults { let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d }

// 1. A Mac that ran CloudShelf: everything moves, the settings come across, the old cache path and login flag go.
let home = root.appending(path: "home1", directoryHint: .isDirectory)
write("Library/Application Support/CloudShelf/drives.json", "[drives]", in: home)
write("Library/Logs/CloudShelf/A.log", "log A", in: home)
write("Library/Caches/CloudShelf/A/vfs/remote/pending.mkv", "not uploaded yet", in: home)
write("Library/Caches/CloudShelf/A/finderMeta/remote.json", "{tags}", in: home)
let d1 = suite("docklume.migration.test1")
let former: [String: Any] = ["showMenuBarExtra": false, "notesSeenVersion": "0.2", "openAtLoginOffered": true,
                             "cacheBase": home.appending(path: "Library/Caches/CloudShelf").path]
FormerName.migrate(home: home, defaults: d1, former: former, busyCaches: [])
check("drives.json repris", read("Library/Application Support/Docklume/drives.json", in: home) == "[drives]")
check("journal repris", read("Library/Logs/Docklume/A.log", in: home) == "log A")
check("fichier en attente d'envoi repris", read("Library/Caches/Docklume/A/vfs/remote/pending.mkv", in: home) == "not uploaded yet")
check("tags du Finder repris", read("Library/Caches/Docklume/A/finderMeta/remote.json", in: home) == "{tags}")
check("anciens dossiers vides", !fm.fileExists(atPath: home.appending(path: "Library/Caches/CloudShelf").path)
      && !fm.fileExists(atPath: home.appending(path: "Library/Logs/CloudShelf").path)
      && !fm.fileExists(atPath: home.appending(path: "Library/Application Support/CloudShelf").path))
check("réglage repris", d1.object(forKey: "showMenuBarExtra") as? Bool == false && d1.string(forKey: "notesSeenVersion") == "0.2")
check("ancien chemin du cache oublié", d1.object(forKey: "cacheBase") == nil)
check("ouverture de session proposée à nouveau", d1.object(forKey: "openAtLoginOffered") == nil)

// 2. Run again with CloudShelf's folders back: nothing is overwritten, the settings Docklume changed stay.
write("Library/Application Support/CloudShelf/drives.json", "[old again]", in: home)
d1.set(true, forKey: "showMenuBarExtra")
FormerName.migrate(home: home, defaults: d1, former: former, busyCaches: [])
check("deuxième lancement : rien d'écrasé", read("Library/Application Support/Docklume/drives.json", in: home) == "[drives]")
check("deuxième lancement : réglage de Docklume gardé", d1.object(forKey: "showMenuBarExtra") as? Bool == true)

// 3. A cache folder elsewhere stays where it is, and stays set.
let home3 = root.appending(path: "home3", directoryHint: .isDirectory)
let d3 = suite("docklume.migration.test3")
FormerName.migrate(home: home3, defaults: d3, former: ["cacheBase": "/Volumes/Disque/Caches CloudShelf"], busyCaches: [])
check("cache personnalisé gardé", d3.string(forKey: "cacheBase") == "/Volumes/Disque/Caches CloudShelf")

// 4. An rclone still running from CloudShelf's cache: the cache stays and Docklume points at it.
let home4 = root.appending(path: "home4", directoryHint: .isDirectory)
write("Library/Caches/CloudShelf/B/vfs/remote/open.bin", "in use", in: home4)
let d4 = suite("docklume.migration.test4")
let busy = home4.appending(path: "Library/Caches/CloudShelf/B").path
FormerName.migrate(home: home4, defaults: d4, former: [:], busyCaches: [busy])
check("cache en cours d'utilisation laissé en place", read("Library/Caches/CloudShelf/B/vfs/remote/open.bin", in: home4) == "in use")
check("Docklume utilise ce cache", d4.string(forKey: "cacheBase").map { URL(filePath: $0).standardizedFileURL.path } == home4.appending(path: "Library/Caches/CloudShelf").standardizedFileURL.path)

// 5. A Mac without CloudShelf: nothing happens.
let home5 = root.appending(path: "home5", directoryHint: .isDirectory)
let d5 = suite("docklume.migration.test5")
FormerName.migrate(home: home5, defaults: d5, former: nil, busyCaches: [])
check("sans CloudShelf : aucun dossier créé", !fm.fileExists(atPath: home5.path))

for n in [1, 3, 4, 5] { UserDefaults.standard.removePersistentDomain(forName: "docklume.migration.test\(n)") }
print(failures == 0 ? "tout passe" : "\(failures) échec(s)")
exit(failures == 0 ? 0 : 1)
