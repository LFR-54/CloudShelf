import SwiftUI

struct DrivesPage: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        PageScroll {
            if let error = store.loadError {
                EmptyMessage(text: error)
            } else if store.drives.isEmpty {
                if !store.isLoading {
                    VStack(spacing: 16) {
                        Text("Ajoutez un premier lecteur pour le retrouver dans le Finder.")
                            .foregroundStyle(Theme.text2)
                        Button("Ajouter un lecteur") { app.overlay = .add(provider: "webdav") }
                            .buttonStyle(PushButtonStyle.largePrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            } else if filtered.isEmpty {
                EmptyMessage(text: "Aucun lecteur ne correspond à « \(app.query) ».")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { DriveCard(drive: $0) }
                }
            }
        }
    }

    private var filtered: [Drive] {
        let query = app.query.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? store.drives : store.drives.filter { $0.name.lowercased().contains(query) }
    }
}

struct EmptyMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(Theme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
    }
}

struct DriveCard: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.compactLayout) private var compact
    let drive: Drive
    @State private var hovering = false

    var body: some View {
        let actions = DriveActions(store: store, app: app)
        HStack(spacing: 14) {
            ProviderTile(provider: drive.provider, size: 48)
                .frame(width: 52, alignment: .leading)
            details
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(actions)
                .frame(width: compact ? ThroughputBlock.compactWidth : 214, alignment: .trailing)
            // The whole card opens the drive page; a narrow window keeps the room for the name.
            if !compact {
                IconButton(symbol: "chevron.right", size: 34, iconSize: 15, label: "Détails de \(drive.name)") {
                    app.page = .drive(drive.id)
                }
                .frame(width: 30)
            }
            Menu {
                DriveMenuItems(drive: drive, actions: actions)
            } label: {
                IconButtonFace(symbol: "ellipsis", size: 40, iconSize: 17, radius: 10, boxed: true)
                    .rotationEffect(.degrees(90))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions pour \(drive.name)")
        }
        .padding(.vertical, 16)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 14, style: .continuous), hovering ? Theme.controlBorder : Theme.cardBorder)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .onTapGesture { app.page = .drive(drive.id) }
        .contextMenu { DriveMenuItems(drive: drive, actions: actions) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !compact { Badge(text: drive.settings.method.badge) }
                if app.renaming == drive.id {
                    RenameField(drive: drive)
                } else {
                    Text(drive.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .help("Double-cliquez pour renommer")
                        .onTapGesture(count: 2) { app.renaming = drive.id }
                }
                StatePill(kind: drive.status.kind, label: drive.status.label)
            }
            .frame(minHeight: 26)
            Text("\(drive.provider.name) • \(drive.account)")
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .lineBox(13)
                .padding(.top, 1)
            SpaceBar(space: drive.space, height: 5)
                .padding(.top, 9)
            SpaceCaption(space: drive.space)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineBox(12)
                .padding(.top, 6)
            if let error = drive.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            } else if !drive.isMounted, drive.pendingUploads > 0 {
                Text("\(Format.plural(drive.pendingUploads, "fichier")) en attente d'envoi : montez le lecteur pour l'envoyer\(drive.pendingUploads > 1 ? "s" : "").")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.orangeInk)
                    .lineLimit(2)
                    .padding(.top, 4)
            } else if let notice = drive.notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.orangeInk)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func trailing(_ actions: DriveActions) -> some View {
        switch drive.state {
        case .mounted:
            ThroughputBlock(read: drive.readSpeed, write: drive.writeSpeed, compact: compact)
        case .mounting, .unmounting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(drive.state == .mounting ? "Montage…" : "Démontage…")
                    .foregroundStyle(Theme.text2)
            }
        case .unmounted, .failed:
            Button(drive.errorMessage == nil ? "Monter" : "Réessayer") { actions.run(.mount, drive) }
                .buttonStyle(PushButtonStyle(height: 30, padding: 18))
        }
    }
}

/// "0,69 To libres sur 2,00 To · Presque plein".
struct SpaceCaption: View {
    let space: Space?

    var body: some View {
        let level = SpaceLevel(space)
        if let total = level.total, let free = level.free {
            if level.isNearlyFull {
                Text("\(Format.capacity(free)) libres sur \(Format.capacity(total)) · \(Text("Presque plein").foregroundStyle(Theme.red).fontWeight(.medium))")
                    .monospacedDigit()
            } else {
                Text("\(Format.capacity(free)) libres sur \(Format.capacity(total))")
                    .monospacedDigit()
            }
        } else {
            Text(space == nil ? "Espace en cours de lecture…" : "Espace non communiqué par ce service")
        }
    }
}

/// Read and write side by side on a mounted card; one above the other, without labels, in a narrow window.
struct ThroughputBlock: View {
    static let compactWidth: CGFloat = 112
    let read: Double
    let write: Double
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 2) {
                line(symbol: "arrow.down", value: read, label: "Lecture")
                line(symbol: "arrow.up", value: write, label: "Écriture")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: Self.compactWidth, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: 12) {
                cell("Lecture", symbol: "arrow.down", value: read)
                cell("Écriture", symbol: "arrow.up", value: write)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 214)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func line(symbol: String, value: Double, label: String) -> some View {
        let active = value >= Format.idleThreshold
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text(active ? Format.speed(value) : "Inactif")
                .font(.system(size: 14, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.text : Theme.text3)
                .monospacedDigit()
                .lineLimit(1)
                .lineBox(14)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(active ? Format.speed(value) : "inactif")")
    }

    private func cell(_ label: String, symbol: String, value: Double) -> some View {
        let active = value >= Format.idleThreshold
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .lineBox(12)
            Text(active ? Format.speed(value) : "Inactif")
                .font(.system(size: 16, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.text : Theme.text3)
                .monospacedDigit()
                .lineLimit(1)
                .lineBox(16)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline rename of a card title: Return keeps, Escape cancels, leaving the field keeps.
private struct RenameField: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    let drive: Drive
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($focused)
                .padding(.horizontal, 6)
                .frame(width: 280, height: 26)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .hairlineBorder(RoundedRectangle(cornerRadius: 6, style: .continuous), Theme.accent)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accentSoft).padding(-3))
                .padding(.leading, -7)
                .onSubmit(commit)
                .onExitCommand { app.renaming = nil }
                .onChange(of: text) { error = nil }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, app.renaming == drive.id {
                        app.renaming = nil
                        store.rename(drive, to: text)
                    }
                }
                .accessibilityLabel("Nouveau nom de \(drive.name)")
            if let error {
                FieldError(message: error)
            }
        }
        .onAppear {
            text = drive.name
            focused = true
        }
    }

    private func commit() {
        if let message = store.rename(drive, to: text) {
            error = message
            focused = true
        } else {
            app.renaming = nil
        }
    }
}
