import Foundation
import ServiceManagement

/// App-wide settings from the Paramètres page, kept in the user defaults.
@MainActor @Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    var showMenuBarExtra: Bool { didSet { defaults.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var showSpeedInMenuBar: Bool { didSet { defaults.set(showSpeedInMenuBar, forKey: "showSpeedInMenuBar") } }
    var notifyMountFailure: Bool { didSet { defaults.set(notifyMountFailure, forKey: "notifyMountFailure") } }
    var notifySessionExpired: Bool { didSet { defaults.set(notifySessionExpired, forKey: "notifySessionExpired") } }
    var notifyNearlyFull: Bool { didSet { defaults.set(notifyNearlyFull, forKey: "notifyNearlyFull") } }
    var defaultMethod: MountMethod { didSet { defaults.set(defaultMethod.rawValue, forKey: "defaultMethod") } }
    var defaultProfile: Profile { didSet { defaults.set(defaultProfile.rawValue, forKey: "defaultProfile") } }
    var cacheBase: URL { didSet { defaults.set(cacheBase.path, forKey: "cacheBase") } }
    var showNotesAfterUpdate: Bool { didSet { defaults.set(showNotesAfterUpdate, forKey: "showNotesAfterUpdate") } }
    /// The last version whose notes were opened, which clears the dot on the notes button.
    var notesSeenVersion: String? { didSet { defaults.set(notesSeenVersion, forKey: "notesSeenVersion") } }

    /// Mirrors the login item; turning it on asks macOS to open CloudShelf at login.
    var openAtLogin: Bool {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                try openAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                openAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "showMenuBarExtra": true, "showSpeedInMenuBar": true,
            "notifyMountFailure": true, "notifySessionExpired": true, "notifyNearlyFull": true,
            "showNotesAfterUpdate": true
        ])
        showMenuBarExtra = defaults.bool(forKey: "showMenuBarExtra")
        showSpeedInMenuBar = defaults.bool(forKey: "showSpeedInMenuBar")
        notifyMountFailure = defaults.bool(forKey: "notifyMountFailure")
        notifySessionExpired = defaults.bool(forKey: "notifySessionExpired")
        notifyNearlyFull = defaults.bool(forKey: "notifyNearlyFull")
        defaultMethod = defaults.string(forKey: "defaultMethod").flatMap(MountMethod.init) ?? .nfs
        defaultProfile = defaults.string(forKey: "defaultProfile").flatMap(Profile.init) ?? .documents
        cacheBase = defaults.string(forKey: "cacheBase").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? MountOptions.defaultCacheBase
        showNotesAfterUpdate = defaults.bool(forKey: "showNotesAfterUpdate")
        notesSeenVersion = defaults.string(forKey: "notesSeenVersion")
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    static let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}
