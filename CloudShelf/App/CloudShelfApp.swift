import SwiftUI

@main
struct CloudShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DriveStore()
    @State private var app = AppState()

    var body: some Scene {
        Window("CloudShelf", id: "main") {
            MainWindow()
                .environment(store)
                .environment(app)
                .frame(minWidth: MainWindow.minimumSize.width, minHeight: MainWindow.minimumSize.height)
                .task {
                    delegate.store = store
                    delegate.app = app
                    await store.load()
                    let preferences = store.preferences
                    if preferences.showNotesAfterUpdate, let seen = preferences.notesSeenVersion, seen != Preferences.appVersion {
                        app.overlay = .notes
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de CloudShelf") { app.overlay = .about }
            }
            CommandGroup(replacing: .newItem) {
                Button("Ajouter un lecteur…") { app.overlay = .add(provider: "webdav") }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                Button("Notes de version") { app.overlay = .notes }
            }
        }

        MenuBarExtra(isInserted: Bindable(store.preferences).showMenuBarExtra) {
            MenuBarPanel()
                .environment(store)
                .environment(app)
        } label: {
            MenuBarLabel(store: store)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: DriveStore?
    var app: AppState?

    /// With the menu bar panel the app keeps running after its window closes.
    @MainActor
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(store?.preferences.showMenuBarExtra ?? true)
    }

    /// Unmounts every drive before quitting so no volume is left without its rclone process.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasActiveMounts else { return .terminateNow }
        // ⌘Q skips the panel's confirmation: files still being uploaded would only leave at the next mount.
        if store.pendingUploadCount > 0, app?.quitConfirmed != true {
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
