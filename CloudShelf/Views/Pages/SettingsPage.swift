import SwiftUI
import UniformTypeIdentifiers

struct SettingsPage: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var preferences = store.preferences
        PageScroll {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "Général", top: 4)
                SettingsGroup {
                    SettingsRow("Ouvrir CloudShelf à l'ouverture de session",
                                hint: preferences.loginItemProblem ?? (preferences.showMenuBarExtra ? "Fenêtre fermée, dans la barre des menus." : nil)) {
                        SwitchToggle(isOn: $preferences.openAtLogin, label: "Ouvrir à l'ouverture de session")
                    }
                    SettingsRow("Afficher dans la barre des menus",
                                hint: preferences.showMenuBarExtra ? "CloudShelf y reste quand la fenêtre est fermée." : "Fermer la fenêtre quitte CloudShelf.") {
                        SwitchToggle(isOn: $preferences.showMenuBarExtra, label: "Afficher dans la barre des menus")
                    }
                    SettingsRow("Afficher le débit dans la barre des menus", hint: nil as String?) {
                        SwitchToggle(isOn: $preferences.showSpeedInMenuBar, label: "Afficher le débit")
                    }
                }
                SectionTitle(text: "Notifications")
                SettingsGroup {
                    SettingsRow("Échec de montage", hint: nil as String?) {
                        SwitchToggle(isOn: $preferences.notifyMountFailure, label: "Notifier les échecs de montage")
                    }
                    SettingsRow("Session expirée", hint: "Quand un service demande de se reconnecter.") {
                        SwitchToggle(isOn: $preferences.notifySessionExpired, label: "Notifier les sessions expirées")
                    }
                    SettingsRow("Espace presque plein", hint: "À partir de 90 % d'occupation.") {
                        SwitchToggle(isOn: $preferences.notifyNearlyFull, label: "Notifier l'espace presque plein")
                    }
                }
                SectionTitle(text: "Nouveaux lecteurs")
                SettingsGroup {
                    SettingsRow("Méthode par défaut", hint: MacFUSE.version.map { "macFUSE \($0) détecté." } ?? "macFUSE n'est pas installé : les lecteurs passent par le client NFS de macOS.") {
                        PopupButton(selection: $preferences.defaultMethod, options: MountMethod.allCases, title: \.rawValue, isEnabled: \.isAvailable)
                    }
                    SettingsRow("Profil par défaut", hint: nil as String?) {
                        PopupButton(selection: $preferences.defaultProfile, options: Profile.allCases, title: \.rawValue)
                    }
                }
                SectionTitle(text: "Cache")
                SettingsGroup {
                    SettingsRow("Emplacement", hint: Text(Drive.abbreviate(preferences.cacheBase.path(percentEncoded: false))).font(.system(size: 11, design: .monospaced))) {
                        Button("Modifier…", action: chooseCacheFolder)
                            .buttonStyle(PushButtonStyle())
                    }
                    SettingsRow("Espace utilisé", hint: "\(Format.gigabytes(store.totalCacheBytes)) pour \(Format.plural(store.drives.count, "lecteur"))") {
                        Button("Vider tout le cache…", action: clearAll)
                            .buttonStyle(PushButtonStyle())
                    }
                }
                SectionTitle(text: "Configuration")
                SettingsGroup {
                    SettingsRow("Importer depuis rclone", hint: importHint) {
                        Button("Importer…", action: importRemotes)
                            .buttonStyle(PushButtonStyle())
                            .disabled(store.importableRemotes.isEmpty)
                    }
                    SettingsRow("Exporter les lecteurs", hint: "Noms, remotes et réglages, sans les mots de passe ni les jetons qui restent dans rclone.conf.") {
                        Button("Exporter…", action: export)
                            .buttonStyle(PushButtonStyle())
                    }
                }
                SectionTitle(text: "Moteur")
                SettingsGroup {
                    SettingsRow("rclone \(store.engineRelease ?? "…")", hint: engineHint) {
                        Button("Rechercher une mise à jour", action: checkUpdate)
                            .buttonStyle(PushButtonStyle())
                    }
                }
            }
        }
    }

    private var configPath: String { Drive.abbreviate(store.configPath ?? "~/.config/rclone/rclone.conf") }

    private var importHint: Text {
        let count = store.importableRemotes.count
        let path = Text(configPath).font(.system(size: 11, design: .monospaced))
        return count == 0
            ? Text("Tous les remotes de \(path) sont des lecteurs.")
            : Text("\(Format.plural(count, "remote")) à importer dans \(path)")
    }

    private var engineHint: String {
        guard let rclone = Rclone.locate() else { return "Introuvable" }
        return rclone.isBundled ? "Inclus avec CloudShelf : 16 connexions partagées entre les fichiers lus." : "Installé dans \(Drive.abbreviate(rclone.executable.deletingLastPathComponent().path(percentEncoded: false)))"
    }

    private func chooseCacheFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Les caches y sont déplacés, avec les fichiers pas encore envoyés. Les lecteurs montés sont remontés."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let remounts = store.hasActiveMounts
        Task {
            await store.moveCaches(to: folder)
            app.show(remounts ? "Emplacement du cache modifié, lecteurs remontés" : "Emplacement du cache modifié")
        }
    }

    private func clearAll() {
        let interrupted = store.hasActiveMounts ? " Les volumes montés sont remontés : les lectures en cours s'interrompent." : ""
        app.confirm("Vider tout le cache ?",
                    message: "Les fichiers lus seront retéléchargés à la prochaine lecture. Ceux qui n'ont pas encore été envoyés sont conservés.\(interrupted)",
                    confirm: "Vider") {
            let before = store.totalCacheBytes
            Task {
                let kept = await store.clearAllCaches()
                let freed = Format.gigabytes(max(0, before - store.totalCacheBytes))
                app.show(kept.files == 0 ? "\(freed) libérés" : "\(freed) libérés, \(Format.plural(kept.files, "fichier")) en attente d'envoi conservé\(kept.files > 1 ? "s" : "")")
            }
        }
    }

    private func importRemotes() {
        let count = store.importableRemotes.count
        app.confirm("Importer \(Format.plural(count, "remote")) ?",
                    message: "Ils apparaissent comme lecteurs non montés. Le fichier rclone.conf n'est pas modifié.",
                    confirm: "Importer") {
            Task {
                let imported = await store.importRemotes()
                app.show("\(Format.plural(imported, "lecteur")) importé\(imported > 1 ? "s" : "") depuis rclone.conf")
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CloudShelf lecteurs.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            app.show("Lecteurs exportés sans les mots de passe")
        } catch {
            app.show(error.localizedDescription, warning: true)
        }
    }

    private func checkUpdate() {
        Task {
            do {
                app.show(try await store.checkEngineUpdate())
            } catch {
                app.show(error.localizedDescription, warning: true)
            }
        }
    }
}
