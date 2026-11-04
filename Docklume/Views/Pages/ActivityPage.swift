import SwiftUI

struct ActivityPage: View {
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 0) {
                stats
                SectionTitle(text: "Débit de lecture")
                ThroughputChart(drives: store.drives, total: store.readHistory)
                    .frame(height: 150)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .card()
                SectionTitle(text: "Lecteurs")
                table
                SectionTitle(text: "Envois")
                SettingsGroup {
                    if store.uploads.isEmpty {
                        Text("Aucun envoi en cours.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    } else {
                        ForEach(store.uploads, id: \.upload.id) { item in
                            UploadRow(drive: item.drive, upload: item.upload)
                        }
                    }
                }
            }
        }
    }

    private var stats: some View {
        let fuse = store.drives.filter { $0.isMounted && $0.settings.method == .macFUSE }.count
        let nfs = store.drives.filter { $0.isMounted && $0.settings.method == .nfs }.count
        let uploads = store.uploads.count
        return TileRow(spacing: 10) {
            StatTile(label: "Lecture", value: Format.speed(store.totalRead)) {
                StatSub(text: "Tous les lecteurs")
            }
            StatTile(label: "Écriture", value: Format.speed(store.totalWrite)) {
                StatSub(text: uploads == 0 ? "Aucun envoi en cours" : "\(Format.plural(uploads, "fichier")) en cours")
            }
            StatTile(label: "Lecteurs montés", value: "\(store.mountedCount) sur \(store.drives.count)") {
                StatSub(text: fuse > 0 ? "\(fuse) via macFUSE, \(nfs) via NFS" : "\(nfs) via NFS")
            }
            StatTile(label: "Cache", value: Format.gigabytes(store.totalCacheBytes)) {
                LevelBar(fraction: store.totalCacheMaxGB > 0 ? Double(store.totalCacheBytes) / (Double(store.totalCacheMaxGB) * 1e9) : 0)
                    .padding(.top, 8)
                StatSub(text: "sur \(store.totalCacheMaxGB) Go")
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            ColumnsLayout {
                Text("Nom")
                Text("État")
                Text("Lecture").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Écriture").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Espace libre")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 12)
            .frame(height: 30)
            ForEach(store.drives) { drive in
                Hairline()
                DriveTableRow(drive: drive) { app.page = .drive(drive.id) }
            }
        }
        .card()
    }
}

/// The table's columns: 2.2, 1.1, 0.9, 0.9 and 1.4 parts of the width, 12 pt apart.
struct ColumnsLayout: Layout {
    var fractions: [CGFloat] = [2.2, 1.1, 0.9, 0.9, 1.4]
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = columnWidths(proposal.width ?? 600)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 600, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func columnWidths(_ total: CGFloat) -> [CGFloat] {
        let unit = max(0, total - spacing * CGFloat(fractions.count - 1)) / fractions.reduce(0, +)
        return fractions.map { $0 * unit }
    }
}

private struct DriveTableRow: View {
    let drive: Drive
    let open: () -> Void

    var body: some View {
        Hovering { hovering in
            ColumnsLayout {
                HStack(spacing: 9) {
                    ProviderTile(provider: drive.provider, size: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(drive.name).lineLimit(1)
                        Text("\(drive.provider.name) · \(drive.settings.method.rawValue)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusLabel(kind: drive.status.kind, label: drive.status.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(drive.isMounted ? Format.speed(drive.readSpeed) : "—")
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(drive.isMounted ? Format.speed(drive.writeSpeed) : "—")
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack(spacing: 8) {
                    SpaceBar(space: drive.space)
                    Text(SpaceLevel(drive.space).free.map(Format.capacity) ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(hovering ? Theme.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct UploadRow: View {
    let drive: Drive
    let upload: Upload

    var body: some View {
        HStack(spacing: 12) {
            ProviderTile(provider: drive.provider, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(upload.fileName).lineLimit(1)
                Text(upload.folder.isEmpty ? drive.name : "\(drive.name) · \(upload.folder)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LevelBar(fraction: upload.progress)
                .frame(width: 140)
            Text(upload.speed > 0 ? Format.speed(upload.speed) : "En attente")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Total read throughput of the last minute, with a hover readout per drive.
struct ThroughputChart: View {
    let drives: [Drive]
    let total: [Double]
    @State private var hoverIndex: Int?

    private let left: CGFloat = 58, right: CGFloat = 6, top: CGFloat = 8, bottom: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let maximum = scaleTop
            ZStack(alignment: .topLeading) {
                ForEach([0, maximum / 2, maximum], id: \.self) { tick in
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y(tick, maximum, size)))
                        path.addLine(to: CGPoint(x: size.width - right, y: y(tick, maximum, size)))
                    }
                    .stroke(Theme.grid, lineWidth: 1)
                    Text(tick == 0 ? "0" : Format.tick(tick))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                        .frame(width: left - 6, alignment: .trailing)
                        .position(x: (left - 6) / 2, y: y(tick, maximum, size))
                }
                Text("-60 s").axisLabel().position(x: left + 14, y: size.height - 7)
                Text("-30 s").axisLabel().position(x: (left + size.width - right) / 2, y: size.height - 7)
                Text("maintenant").axisLabel().position(x: size.width - right - 27, y: size.height - 7)
                area(size, maximum).fill(Theme.accentSoft)
                line(size, maximum).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let index = hoverIndex {
                    let point = CGPoint(x: x(index, size), y: y(total[index], maximum, size))
                    Path { path in
                        path.move(to: CGPoint(x: point.x, y: top))
                        path.addLine(to: CGPoint(x: point.x, y: size.height - bottom))
                    }
                    .stroke(Theme.text3, lineWidth: 1)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.window, lineWidth: 2))
                        .position(point)
                    tooltip(index)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            let width = dimensions.width
                            return -(point.x + 24 + width > size.width ? max(8, point.x - width) : point.x + 24)
                        }
                        .alignmentGuide(.top) { _ in -18 }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = (location.x - left) / max(1, size.width - left - right)
                    hoverIndex = min(total.count - 1, max(0, Int((fraction * CGFloat(total.count - 1)).rounded())))
                case .ended:
                    hoverIndex = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Débit de lecture total sur les 60 dernières secondes")
        .accessibilityValue(Format.speed(total.last ?? 0))
    }

    private var scaleTop: Double { ChartScale.top(total) }

    private func x(_ index: Int, _ size: CGSize) -> CGFloat {
        left + CGFloat(index) / CGFloat(max(1, total.count - 1)) * (size.width - left - right)
    }

    private func y(_ value: Double, _ maximum: Double, _ size: CGSize) -> CGFloat {
        top + (1 - CGFloat(value / maximum)) * (size.height - top - bottom)
    }

    private func line(_ size: CGSize, _ maximum: Double) -> Path {
        Path { path in
            path.addLines(total.indices.map { CGPoint(x: x($0, size), y: y(total[$0], maximum, size)) })
        }
    }

    private func area(_ size: CGSize, _ maximum: Double) -> Path {
        Path { path in
            guard !total.isEmpty else { return }
            path.move(to: CGPoint(x: x(0, size), y: y(0, maximum, size)))
            total.indices.forEach { path.addLine(to: CGPoint(x: x($0, size), y: y(total[$0], maximum, size))) }
            path.addLine(to: CGPoint(x: x(total.count - 1, size), y: y(0, maximum, size)))
            path.closeSubpath()
        }
    }

    private func tooltip(_ index: Int) -> some View {
        let ago = total.count - 1 - index
        return VStack(alignment: .leading, spacing: 1) {
            Text(ago == 0 ? "Maintenant" : "Il y a \(ago) s")
                .foregroundStyle(Theme.text2)
                .padding(.bottom, 2)
            tooltipLine(total[index], "Total", strong: true)
            ForEach(drives.filter { $0.history.indices.contains(index) && $0.history[index] >= Format.idleThreshold }) { drive in
                tooltipLine(drive.history[index], drive.name, strong: false)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minWidth: 150, alignment: .leading)
        .background(Theme.tooltip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 8, style: .continuous), Theme.cardBorder)
        .shadow(color: .black.opacity(0.14), radius: 9, y: 6)
    }

    private func tooltipLine(_ value: Double, _ label: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 10, height: 2).opacity(strong ? 1 : 0)
            Text(Format.speed(value))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(minWidth: 58, alignment: .leading)
            Text(label).foregroundStyle(Theme.text2)
        }
        .font(.system(size: strong ? 13 : 11))
    }
}

private extension Text {
    func axisLabel() -> some View {
        font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.text3)
    }
}
