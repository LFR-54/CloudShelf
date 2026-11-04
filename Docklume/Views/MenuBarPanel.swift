import SwiftUI

/// The menu bar panel: throughput, every drive with a mount button, uploads in progress.
struct MenuBarPanel: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// 5 pt padding around a 13 pt name and an 11 pt line, at the mockup's 1.4 line height.
    private let rowHeight: CGFloat = 43.6
    private let listHeight: CGFloat = 232

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            rates
            section("Lecteurs", detail: "\(store.drives.count)")
            driveList
            let uploads = store.uploads.filter { $0.upload.bytes > 0 }
            if !uploads.isEmpty {
                section("Envois", detail: Format.speed(store.totalWrite))
                ForEach(uploads, id: \.upload.id) { item in
                    HStack(spacing: 9) {
                        ProviderTile(provider: item.drive.provider, size: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.upload.fileName).lineLimit(1).truncationMode(.middle)
                            LevelBar(fraction: item.upload.progress, height: 3)
                        }
                        Text("\(Int(item.upload.progress * 100)) %")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
            separator
            PanelItem(title: "Ouvrir Docklume") { open(.drives) }
            separator
            PanelItem(title: "Quitter Docklume", shortcut: "⌘Q", action: quit)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .padding(6)
        .frame(width: 344)
    }

    private var head: some View {
        HStack(spacing: 10) {
            AppLogo(size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Docklume").fontWeight(.semibold).lineBox(13)
                Text("\(Format.plural(store.mountedCount, "monté")) sur \(Format.plural(store.drives.count, "lecteur"))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineBox(11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundButton(symbol: "plus", label: "Ajouter un lecteur") {
                open(nil)
                app.overlay = .add(provider: "webdav")
            }
            RoundButton(symbol: "gearshape", label: "Paramètres") { open(.settings) }
        }
        .padding(.top, 8)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.bottom, 10)
    }

    private var rates: some View {
        ThroughputCard(read: store.totalRead, write: store.totalWrite,
                       readHistory: store.readHistory, writeHistory: store.writeHistory)
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
    }

    private func section(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Text(detail).monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text2)
        .lineBox(11)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }

    /// Scrolls past five or six drives, with a hairline under the list when it does.
    private var driveList: some View {
        let height = CGFloat(store.drives.count) * rowHeight
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(store.drives) { drive in
                    PanelDriveRow(drive: drive) {
                        if drive.isMounted {
                            store.showInFinder(drive)
                            dismiss()
                        } else if !drive.isBusy {
                            store.mount(drive)
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
        .scrollIndicators(height > listHeight ? .automatic : .never)
        .scrollDisabled(height <= listHeight)
        .frame(height: min(height, listHeight))
        .overlay(alignment: .bottom) {
            if height > listHeight { Hairline(color: Color(nsColor: .separatorColor)) }
        }
    }

    /// The system separator colour: the panel is translucent, and a fixed grey vanishes over a dark desktop.
    private var separator: some View {
        Hairline(color: Color(nsColor: .separatorColor)).padding(.horizontal, 10).padding(.vertical, 6)
    }

    /// Brings the main window forward, on a page when given.
    private func open(_ page: AppState.Page?) {
        dismiss()
        let joinedDock = DockIcon.show()
        openWindow(id: AppDelegate.mainWindow)
        if joinedDock {
            DispatchQueue.main.async { NSApp.activate() }
        } else {
            NSApp.activate()
        }
        if let page { app.page = page }
    }

    private func quit() {
        let count = store.mountedCount
        guard count > 0 else {
            NSApp.terminate(nil)
            return
        }
        open(nil)
        let pending = store.pendingUploadCount
        app.confirm("Quitter Docklume ?",
                    message: "\(Format.plural(count, "lecteur")) monté\(count > 1 ? "s seront démontés" : " sera démonté"). "
                        + (pending > 0 ? DriveStore.unsentMessage(pending) : "Les envois non terminés reprendront au prochain montage."),
                    confirm: "Quitter") {
            app.quitConfirmed = true
            NSApp.terminate(nil)
        }
    }
}

private struct PanelDriveRow: View {
    let drive: Drive
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hovering { hovering in
                HStack(spacing: 10) {
                    ProviderTile(provider: drive.provider, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(drive.name)
                            .foregroundStyle(drive.isMounted ? Theme.text : Theme.text2)
                            .lineLimit(1)
                            .lineBox(13)
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .lineBox(11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if drive.isMounted {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text3)
                            .opacity(hovering ? 1 : 0)
                    } else if drive.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Monter")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hovering ? .white : Theme.text)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(hovering ? Theme.accent : Theme.separator, in: Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxHeight: .infinity)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(drive.isMounted ? "Afficher dans le Finder" : "Monter")
    }

    private var line: String {
        switch drive.state {
        case .unmounted: return "Non monté"
        case .mounting: return "Montage…"
        case .unmounting: return "Démontage…"
        case .failed: return "Échec du montage"
        case .mounted:
            let reading = drive.readSpeed >= Format.idleThreshold ? "↓ \(Format.speed(drive.readSpeed))" : ""
            let writing = drive.writeSpeed >= Format.idleThreshold ? "↑ \(Format.speed(drive.writeSpeed))" : ""
            let activity = [reading, writing].filter { !$0.isEmpty }.joined(separator: " ")
            let free = SpaceLevel(drive.space).free.map { " · \(Format.capacity($0)) libres" } ?? ""
            return (activity.isEmpty ? "Inactif" : activity) + free
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hovering { hovering in
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(hovering ? Theme.controlBorder : Theme.separator, in: Circle())
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PanelItem: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hovering { hovering in
                HStack {
                    Text(title)
                    Spacer()
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 12))
                            .foregroundStyle(hovering ? .white.opacity(0.75) : Theme.text3)
                    }
                }
                .foregroundStyle(hovering ? .white : Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(hovering ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// Read and write throughput of the last minute on one scale, which follows the busiest second,
/// with both values under the pointer.
struct ThroughputCard: View {
    let read: Double
    let write: Double
    let readHistory: [Double]
    let writeHistory: [Double]
    @State var hover: Int?

    private let chartHeight: CGFloat = 64
    /// Room above the plot for the scale label, so it never sits on the data.
    private let labelBand: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                figure("Lecture", symbol: "arrow.down", value: read, color: Theme.accent)
                figure("Écriture", symbol: "arrow.up", value: write, color: Theme.upload)
            }
            chart
                .frame(height: chartHeight + labelBand)
                .padding(.top, 2)
            HStack {
                Text("-60 s")
                Spacer()
                Text("maintenant")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.text3)
            .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Débit de la dernière minute")
        .accessibilityValue("Lecture \(Format.speed(read)), écriture \(Format.speed(write))")
    }

    /// The series' line key, its name and its current value.
    private func figure(_ label: String, symbol: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Capsule().fill(color).frame(width: 10, height: 2.5)
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(label)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .lineBox(11)
            Text(Format.speed(value))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineBox(17)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let top = ChartScale.top(readHistory + writeHistory)
            ZStack(alignment: .topLeading) {
                Text(Format.tick(top))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
                    .frame(width: width, alignment: .trailing)
                    .offset(y: -1)
                ForEach([0.0, top], id: \.self) { tick in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(tick, top)))
                        path.addLine(to: CGPoint(x: width, y: y(tick, top)))
                    }
                    .stroke(Theme.grid, lineWidth: 1)
                }
                area(readHistory, top, width).fill(Theme.accent.opacity(0.12))
                line(writeHistory, top, width).stroke(Theme.upload, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                line(readHistory, top, width).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let index = hover {
                    let x = x(index, width)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: labelBand))
                        path.addLine(to: CGPoint(x: x, y: labelBand + chartHeight))
                    }
                    .stroke(Theme.text3, lineWidth: 1)
                    dot(Theme.upload, at: CGPoint(x: x, y: y(value(writeHistory, index), top)))
                    dot(Theme.accent, at: CGPoint(x: x, y: y(value(readHistory, index), top)))
                    tooltip(index)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            -(x + 12 + dimensions.width > width ? x - 12 - dimensions.width : x + 12)
                        }
                        .alignmentGuide(.top) { _ in -labelBand }
                } else if let last = readHistory.indices.last {
                    dot(Theme.accent, at: CGPoint(x: width, y: y(readHistory[last], top)))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let count = max(readHistory.count, 2)
                    hover = min(count - 1, max(0, Int((location.x / max(1, width) * CGFloat(count - 1)).rounded())))
                case .ended:
                    hover = nil
                }
            }
        }
    }

    private func value(_ series: [Double], _ index: Int) -> Double {
        series.indices.contains(index) ? series[index] : 0
    }

    private func x(_ index: Int, _ width: CGFloat) -> CGFloat {
        CGFloat(index) / CGFloat(max(1, readHistory.count - 1)) * width
    }

    private func y(_ value: Double, _ top: Double) -> CGFloat {
        labelBand + (1 - CGFloat(min(value, top) / top)) * chartHeight
    }

    private func line(_ series: [Double], _ top: Double, _ width: CGFloat) -> Path {
        Path { path in
            path.addLines(series.indices.map { CGPoint(x: x($0, width), y: y(series[$0], top)) })
        }
    }

    private func area(_ series: [Double], _ top: Double, _ width: CGFloat) -> Path {
        Path { path in
            guard let last = series.indices.last else { return }
            path.move(to: CGPoint(x: x(0, width), y: y(0, top)))
            series.indices.forEach { path.addLine(to: CGPoint(x: x($0, width), y: y(series[$0], top))) }
            path.addLine(to: CGPoint(x: x(last, width), y: y(0, top)))
            path.closeSubpath()
        }
    }

    /// An 8 pt marker with a ring in the card colour, so it stays readable where the lines cross.
    private func dot(_ color: Color, at point: CGPoint) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Theme.cardSolid, lineWidth: 2))
            .position(point)
    }

    private func tooltip(_ index: Int) -> some View {
        let ago = readHistory.count - 1 - index
        return VStack(alignment: .leading, spacing: 2) {
            Text(ago == 0 ? "Maintenant" : "Il y a \(ago) s")
                .foregroundStyle(Theme.text2)
            tooltipLine(value(readHistory, index), "Lecture", Theme.accent)
            tooltipLine(value(writeHistory, index), "Écriture", Theme.upload)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.tooltip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.cardBorder)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func tooltipLine(_ value: Double, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 10, height: 2.5)
            Text(Format.speed(value)).fontWeight(.semibold).foregroundStyle(Theme.text).monospacedDigit()
            Text(label).foregroundStyle(Theme.text2)
        }
    }
}
