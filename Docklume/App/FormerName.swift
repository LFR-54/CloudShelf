import AppKit

/// What the app kept under its former name, CloudShelf, taken over at the first launch of Docklume: the settings,
/// the drives, their caches with the files not uploaded yet and the Finder tags, and the logs.
enum FormerName {
    static let bundleID = "fr.cloudshelf.CloudShelf"
    private static let migrated = "formerNameMigrated"

    /// Both apps would mount the same drives, so Docklume takes over only once CloudShelf has quit.
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Each place moves only while Docklume has none of its own, so running this again changes nothing.
    /// - Parameters:
    ///   - home: the home folder; another one for tests.
    ///   - former: CloudShelf's settings.
    ///   - busyCaches: the cache folders of rclone mounts still running.
    static func migrate(home: URL = FileManager.default.homeDirectoryForCurrentUser, defaults: UserDefaults = .standard,
                        former: [String: Any]? = UserDefaults.standard.persistentDomain(forName: bundleID),
                        busyCaches: [String] = OrphanMount.all().map(\.cacheDirectory)) {
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        func place(_ path: String, _ name: String) -> URL { library.appending(path: "\(path)/\(name)", directoryHint: .isDirectory) }
        let formerCaches = place("Caches", "CloudShelf"), caches = place("Caches", "Docklume")

        if defaults.object(forKey: migrated) == nil, var former {
            // The default cache folder moves below, and the login item is CloudShelf's: Docklume offers its own.
            if (former["cacheBase"] as? String).map({ URL(filePath: $0).standardizedFileURL.path }) == formerCaches.standardizedFileURL.path {
                former.removeValue(forKey: "cacheBase")
            }
            former.removeValue(forKey: "openAtLoginOffered")
            for (key, value) in former where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: migrated)

        move(place("Application Support", "CloudShelf"), to: place("Application Support", "Docklume"))
        move(place("Logs", "CloudShelf"), to: place("Logs", "Docklume"))
        // An rclone that CloudShelf left running writes in its cache folder, so Docklume keeps using it then.
        if busyCaches.contains(where: { $0.hasPrefix(formerCaches.path(percentEncoded: false)) }) {
            if defaults.string(forKey: "cacheBase") == nil, !FileManager.default.fileExists(atPath: caches.path) {
                defaults.set(formerCaches.path(percentEncoded: false), forKey: "cacheBase")
            }
        } else {
            move(formerCaches, to: caches)
        }
    }

    private static func move(_ source: URL, to destination: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { return }
        try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: source, to: destination)
    }
}
