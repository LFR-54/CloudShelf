import SwiftUI

@main
struct CloudShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("CloudShelf", id: AppDelegate.mainWindow) {
            MainWindow()
                .environment(delegate.store)
                .environment(delegate.app)
                .frame(minWidth: MainWindow.minimumSize.width, minHeight: MainWindow.minimumSize.height)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de CloudShelf") { delegate.app.overlay = .about }
            }
            CommandGroup(replacing: .newItem) {
                Button("Ajouter un lecteur…") { delegate.app.overlay = .add(provider: "webdav") }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                Button("Notes de version") { delegate.app.overlay = .notes }
            }
        }

        MenuBarExtra(isInserted: Bindable(delegate.store.preferences).showMenuBarExtra) {
            MenuBarPanel()
                .environment(delegate.store)
                .environment(delegate.app)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The hexagon glyph, followed by the total throughput when something moves.
private struct MenuBarLabel: View {
    let store: DriveStore

    var body: some View {
        let speed = store.totalRead + store.totalWrite
        if store.preferences.showSpeedInMenuBar, speed >= Format.idleThreshold {
            Label(Format.speed(speed), image: "MenuBarIcon")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        } else {
            Image("MenuBarIcon")
        }
    }
}

/// Owns the drives, which load and mount at launch whether the window opens or not.
///
/// CloudShelf is declared a menu bar app (LSUIElement) and joins the Dock while its window is open. Closed, the
/// window leaves it in the menu bar: utilities that quit the Dock apps left without a window, such as Vorssaint,
/// would otherwise stop it and unmount the drives.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindow = "main"

    let store = DriveStore()
    let app = AppState()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before the app is activated, so that it gets the menu bar.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchMainWindow()
        // At login the window stays closed, the drives being in the menu bar. SwiftUI has ordered it in but not
        // drawn it yet.
        if launchedAtLogin, store.preferences.showMenuBarExtra {
            NSApp.windows.first { $0.identifier?.rawValue == Self.mainWindow }?.close()
        }
        store.preferences.enableOpenAtLoginOnce()
        Task {
            await store.load()
            let preferences = store.preferences
            if preferences.showNotesAfterUpdate, let seen = preferences.notesSeenVersion, seen != Preferences.appVersion {
                app.overlay = .notes
            }
        }
    }

    /// macOS marks the launch of a login item in the event that opens the app.
    private var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Takes the app out of the Dock when the window closes, and back in when it opens however it was opened.
    private func watchMainWindow() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard (note.object as? NSWindow)?.identifier?.rawValue == Self.mainWindow, store.preferences.showMenuBarExtra else { return }
        DockIcon.hide()
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard (note.object as? NSWindow)?.identifier?.rawValue == Self.mainWindow, DockIcon.show() else { return }
        DispatchQueue.main.async { NSApp.activate() }
    }

    /// Opening CloudShelf from the Finder, Spotlight or the Dock while it runs in the menu bar: SwiftUI opens the
    /// window once this returns.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if DockIcon.show() { DispatchQueue.main.async { NSApp.activate() } }
        return true
    }

    /// With the menu bar icon the app keeps running after its window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !store.preferences.showMenuBarExtra
    }

    /// Unmounts every drive before quitting so no volume is left without its rclone process.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.hasActiveMounts else { return .terminateNow }
        // ⌘Q skips the panel's confirmation: files still being uploaded would only leave at the next mount.
        if store.pendingUploadCount > 0, !app.quitConfirmed {
            let alert = NSAlert()
            alert.messageText = "Quitter CloudShelf ?"
            alert.informativeText = DriveStore.unsentMessage(store.pendingUploadCount)
            alert.addButton(withTitle: "Quitter")
            alert.addButton(withTitle: "Annuler")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        Task {
            await store.unmountAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The Dock icon, shown while the window is open.
@MainActor
enum DockIcon {
    /// Puts the app in the Dock before its window opens. True when it was not, and the caller then activates it:
    /// an app that joins the Dock while active keeps the menu bar of the previous app until activated again.
    @discardableResult
    static func show() -> Bool {
        guard NSApp.activationPolicy() != .regular else { return false }
        NSApp.setActivationPolicy(.regular)
        if NSApp.isActive { NSApp.deactivate() }
        return true
    }

    /// Leaves the menu bar icon alone, and the menu bar to the app below.
    static func hide() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }
}
