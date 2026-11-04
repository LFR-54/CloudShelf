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
            let service = SMAppService.mainApp
            guard openAtLogin != (service.status == .enabled) else { return }
            loginItemProblem = nil
            do {
                try openAtLogin ? service.register() : service.unregister()
            } catch {
                loginItemProblem = error.localizedDescription
            }
            if openAtLogin, service.status == .requiresApproval {
                loginItemProblem = "En attente de votre accord dans Réglages Système."
                SMAppService.openSystemSettingsLoginItems()
            }
            openAtLogin = service.status == .enabled
        }
    }
    /// Why the login item is off although it was turned on.
    private(set) var loginItemProblem: String?

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

    /// Turns the login item on at the first launch that offers it, as CloudShelf keeps the drives mounted from the
    /// menu bar. Only once, so that turning it off, here or in Réglages Système, lasts.
    func enableOpenAtLoginOnce() {
        guard !defaults.bool(forKey: "openAtLoginOffered") else { return }
        defaults.set(true, forKey: "openAtLoginOffered")
        let service = SMAppService.mainApp
        guard service.status == .notRegistered || service.status == .notFound else { return }
        try? service.register()
        openAtLogin = service.status == .enabled
    }

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    static let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}
