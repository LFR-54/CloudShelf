import SwiftUI

/// The window of the mockup: an inset sidebar, a header and the page, with dialogs and toasts on top.
struct MainWindow: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    @State private var compact = false

    /// Below this width the layout tightens; at and above it, it is the mockup's.
    static let compactWidth: CGFloat = 1000
    static let minimumSize = CGSize(width: 840, height: 580)

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 250)
                .padding(8)
            VStack(spacing: 0) {
                PageHeader()
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .background(Theme.window)
        .overlay { DialogHost() }
        .overlay(alignment: .bottom) { ToastView() }
        .background(WindowChrome())
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: app.overlay)
        .onGeometryChange(for: Bool.self) { $0.size.width < Self.compactWidth } action: { compact = $0 }
        .environment(\.compactLayout, compact)
    }

    @ViewBuilder private var page: some View {
        switch app.page {
        case .drives:
            DrivesPage()
        case .activity:
            ActivityPage()
        case .settings:
            SettingsPage()
        case .drive(let id):
            if let drive = store.drive(id) {
                DriveDetailPage(drive: drive).id(id)
            } else {
                DrivesPage()
            }
        }
    }
}

/// An empty unified toolbar: macOS then sets the window buttons 19 pt in from the corner, inside the sidebar,
/// instead of 9 pt with a bare hidden title bar. Clicks below still reach the content.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.styleMask.contains(.titled), window.toolbar == nil else { return }
            window.toolbar = NSToolbar(identifier: "CloudShelf")
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
}

/// Scrolling page body with the mockup's content insets.
struct PageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.leading, 16)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
    }
}

struct Sidebar: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window buttons end 33 pt from the top of the window; the logo comes 20 pt below, as in the mockup.
            Color.clear.frame(height: 45)
            HStack(spacing: 12) {
                AppLogo(size: 58)
                VStack(alignment: .leading, spacing: 0) {
                    Text("CloudShelf")
                        .font(.system(size: 21, weight: .bold))
                        .tracking(-0.21)
                    Text("Moteur rclone \(store.engineRelease ?? "…")")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text2)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 22)
            NavItem(title: "Lecteurs montés", symbol: "tile-server", selected: isDrives) {
                CountBadge(count: store.mountedCount)
            } action: {
                app.page = .drives
            }
            NavItem(title: "Activité", symbol: "waveform.path.ecg", selected: app.page == .activity) {
                EmptyView()
            } action: {
                app.page = .activity
            }
            NavItem(title: "Ajouter un lecteur", symbol: "plus.circle", selected: false) {
                EmptyView()
            } action: {
                app.overlay = .add(provider: "webdav")
            }
            NavItem(title: "Paramètres", symbol: "gearshape", selected: app.page == .settings) {
                EmptyView()
            } action: {
                app.page = .settings
            }
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 18, style: .continuous), Theme.cardBorder)
    }

    private var isDrives: Bool {
        if case .drive = app.page { return true }
        return app.page == .drives
    }

    private var footer: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CloudShelf")
                    .font(.system(size: 15, weight: .semibold))
                    .lineBox(15, 1.35)
                Text("Version \(Preferences.appVersion)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .lineBox(12.5, 1.35)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FootButton(symbol: "newspaper", label: "Notes de version", showsDot: store.preferences.notesSeenVersion != Preferences.appVersion) {
                app.overlay = .notes
            }
            FootButton(symbol: "info.circle", label: "À propos de CloudShelf", showsDot: false) {
                app.overlay = .about
            }
        }
        .padding(.top, 12)
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.bottom, 14)
    }
}

private struct NavItem<Accessory: View>: View {
    let title: String
    let symbol: String
    let selected: Bool
    @ViewBuilder let accessory: Accessory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hovering { hovering in
                HStack(spacing: 10) {
                    icon
                        .foregroundStyle(selected ? Theme.accent : Theme.text2)
                        .frame(width: 22)
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    accessory
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(selected ? Theme.accentNav : hovering ? Theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Names starting with "tile-" are the mockup's own glyphs in the asset catalog.
    @ViewBuilder private var icon: some View {
        if symbol.hasPrefix("tile-") {
            Image(symbol).renderingMode(.template).resizable().frame(width: 19, height: 19)
        } else {
            Image(systemName: symbol).font(.system(size: 16, weight: .regular))
        }
    }
}

private struct FootButton: View {
    let symbol: String
    let label: String
    let showsDot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hovering { hovering in
                Image(systemName: symbol)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(hovering ? Theme.text : Theme.text2)
                    .frame(width: 32, height: 32)
                    .background(Theme.control, in: Circle())
                    .hairlineBorder(Circle(), Theme.controlBorder)
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 9, height: 9)
                                .background(Circle().fill(Theme.cardSolid).padding(-2))
                                .offset(x: 1, y: -1)
                        }
                    }
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(showsDot ? "\(label), nouvelle version installée" : label)
    }
}

struct AppLogo: View {
    let size: CGFloat
    var shadowRadius: CGFloat = 1.5
    var shadowY: CGFloat = 1

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: shadowRadius, y: shadowY)
            .accessibilityHidden(true)
    }
}

struct PageHeader: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.compactLayout) private var compact

    var body: some View {
        HStack(spacing: 10) {
            titles
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.top, 20)
        .padding(.trailing, 24)
        .padding(.bottom, 14)
        .padding(.leading, 16)
        .frame(minHeight: 76)
    }

    @ViewBuilder private var titles: some View {
        switch app.page {
        case .drives:
            HeaderTitles(title: "Lecteurs montés", subtitle: drivesSubtitle)
        case .activity:
            HeaderTitles(title: "Activité", subtitle: "Débit et transferts des 60 dernières secondes")
        case .settings:
            HeaderTitles(title: "Paramètres", subtitle: "Valeurs par défaut des nouveaux lecteurs et comportement de l'app.")
        case .drive(let id):
            if let drive = store.drive(id) {
                HStack(spacing: 10) {
                    Button { app.page = .drives } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .control(radius: 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityLabel("Retour aux lecteurs")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(drive.name)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                            .lineBox(20)
                        Text("\(drive.provider.name) • \(Text(drive.displayPath).font(.system(size: 12, design: .monospaced)))")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                            .lineBox(13)
                    }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch app.page {
        case .drives:
            HStack(spacing: 10) {
                ToolbarButton(title: "Ajouter", symbol: "plus.circle", tint: Theme.accent) { app.overlay = .add(provider: "webdav") }
                ToolbarButton(title: "Paramètres", symbol: "gearshape") { app.page = .settings }
                SearchField(text: Bindable(app).query, placeholder: "Rechercher…", width: compact ? 150 : 210)
            }
        case .activity:
            ToolbarButton(title: "Tout démonter", symbol: "eject") {
                let unmountAll: @MainActor () -> Void = {
                    Task {
                        await store.unmountAll()
                        app.show("Tous les lecteurs sont démontés")
                    }
                }
                guard store.pendingUploadCount > 0 else { return unmountAll() }
                app.confirm("Tout démonter ?", message: DriveStore.unsentMessage(store.pendingUploadCount), confirm: "Démonter", action: unmountAll)
            }
            .disabled(store.mountedCount == 0)
        case .settings:
            EmptyView()
        case .drive(let id):
            if let drive = store.drive(id) {
                let actions = DriveActions(store: store, app: app)
                HStack(spacing: 10) {
                    ToolbarButton(title: "Afficher dans le Finder", symbol: "folder") { actions.run(.finder, drive) }
                    ToolbarButton(title: drive.isMounted || drive.state == .mounting ? "Démonter" : "Monter", symbol: "eject") {
                        actions.run(.mount, drive)
                    }
                    .disabled(drive.state == .unmounting)
                    Menu {
                        DriveMenuItems(drive: drive, actions: actions)
                    } label: {
                        IconButtonFace(symbol: "ellipsis", size: 34, iconSize: 16, boxed: true)
                            .rotationEffect(.degrees(90))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Autres actions")
                }
            }
        }
    }

    private var drivesSubtitle: String {
        let speed = store.totalRead + store.totalWrite
        return "\(Format.plural(store.mountedCount, "monté")) sur \(store.drives.count) · \(speed >= Format.idleThreshold ? Format.speed(speed) : "aucun transfert")"
    }
}

private struct HeaderTitles: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .lineBox(20)
            Text(subtitle)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .lineBox(13)
                .contentTransition(.numericText())
        }
    }
}

struct ToastView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            if let toast = app.toast {
                HStack(spacing: 9) {
                    Image(systemName: toast.warning ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(toast.warning ? Theme.orange : Theme.green)
                    Text(toast.message)
                        .font(.system(size: 13))
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 640)
                .background(Theme.tooltip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .hairlineBorder(RoundedRectangle(cornerRadius: 12, style: .continuous), Theme.cardBorder)
                .shadow(color: .black.opacity(0.18), radius: 15, y: 10)
                .id(toast.id)
                .transition(.opacity.combined(with: .offset(y: 16)))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.bottom, 22)
        .animation(.easeOut(duration: 0.2), value: app.toast)
        .allowsHitTesting(false)
    }
}
