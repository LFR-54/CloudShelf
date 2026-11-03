import SwiftUI

/// Gives its content the pointer's hover state, for the mockup's :hover styles.
struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering).onHover { hovering = $0 }
    }
}

// MARK: - Buttons

/// Header button with an icon (34 pt high).
/// Icon and title; the icon alone, with the title as its tooltip, in a narrow window.
struct ToolbarButton: View {
    @Environment(\.compactLayout) private var compact
    let title: String
    let symbol: String
    var tint: Color = Theme.text2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                if !compact { Text(title) }
            }
            .fixedSize()
        }
        .buttonStyle(ToolbarButtonStyle(padding: compact ? 8 : 14))
        .help(compact ? title : "")
        .accessibilityLabel(title)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    var padding: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, padding)
                .frame(height: 34)
                .control(radius: 9, fill: hovering ? Theme.hover : Theme.control)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// The mockup's push buttons: regular (26 pt), large (34 pt) and the full-width pair of alerts (30 pt).
struct PushButtonStyle: ButtonStyle {
    enum Kind {
        case normal, primary, destructive, danger
    }

    var kind = Kind.normal
    var height: CGFloat = 26
    var padding: CGFloat = 12
    var radius: CGFloat = 6
    var minWidth: CGFloat?
    var fills = false

    static let large = PushButtonStyle(height: 34, padding: 22, radius: 9, minWidth: 110)
    static let largePrimary = PushButtonStyle(kind: .primary, height: 34, padding: 22, radius: 9, minWidth: 110)

    static func pair(_ kind: Kind = .normal) -> PushButtonStyle {
        PushButtonStyle(kind: kind, height: 30, padding: 12, radius: 8, fills: true)
    }

    func makeBody(configuration: Configuration) -> some View {
        PushButtonBody(configuration: configuration, style: self)
    }
}

private struct PushButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let style: PushButtonStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: style.kind == .primary || style.kind == .danger ? .medium : .regular))
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, style.padding)
            .frame(minWidth: style.minWidth, maxWidth: style.fills ? .infinity : nil)
            .frame(height: style.height)
            .control(radius: style.radius, fill: fill, border: filled ? .clear : Theme.controlBorder)
            .brightness(configuration.isPressed ? (filled ? -0.08 : -0.04) : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }

    private var filled: Bool { style.kind == .primary || style.kind == .danger }

    private var fill: Color {
        switch style.kind {
        case .primary: Theme.accent
        case .danger: Theme.red
        default: Theme.control
        }
    }

    private var ink: Color {
        switch style.kind {
        case .primary, .danger: .white
        case .destructive: Theme.red
        case .normal: Theme.text
        }
    }
}

/// Borderless icon button that shows a hover fill; boxed adds the control border.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 15
    var radius: CGFloat = 8
    var boxed = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonFace(symbol: symbol, size: size, iconSize: iconSize, radius: radius, boxed: boxed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct IconButtonFace: View {
    let symbol: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 15
    var radius: CGFloat = 8
    var boxed = false

    var body: some View {
        Hovering { hovering in
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: size, height: size)
                .background {
                    if boxed {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(hovering ? Theme.hover : Theme.control)
                            .hairlineBorder(RoundedRectangle(cornerRadius: radius, style: .continuous), Theme.controlBorder)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.hover)
                    }
                }
                .contentShape(Rectangle())
        }
    }
}

/// Round close button of the dialogs.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 32, height: 32)
                .background(Theme.control, in: Circle())
                .hairlineBorder(Circle(), Theme.controlBorder)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fermer")
    }
}

// MARK: - Toggles and pickers

/// The mockup's green switch, 38 × 22 pt.
struct SwitchToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.green : Theme.separator)
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "activé" : "désactivé")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Pop-up button, 26 pt high, opening a native menu.
struct PopupButton<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var isEnabled: (Value) -> Bool = { _ in true }

    var body: some View {
        PopupMenu(title: title(selection), widest: options.map(title)) {
            ForEach(options, id: \.self) { option in
                Toggle(title(option), isOn: Binding(get: { option == selection }, set: { if $0 { selection = option } }))
                    .disabled(!isEnabled(option))
            }
        }
    }
}

/// Pop-up face with free menu content, for menus that mix choices and actions.
struct PopupMenu<Content: View>: View {
    let title: String
    /// Every title the button can show; it takes the width of the longest.
    var widest: [String] = []
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    ForEach(widest, id: \.self) { Text($0).hidden() }
                    Text(title)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.text2)
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .frame(height: 26)
            .control(radius: 6)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if option == selection {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Theme.segmentOn)
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.separator, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Fields

/// Text field of the forms (30 pt) and settings rows (26 pt), with the accent focus ring.
struct FieldBox: View {
    @Binding var text: String
    var placeholder = ""
    var secure = false
    var height: CGFloat = 30
    var invalid = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .background(alignment: .leading) { Placeholder(text: placeholder, visible: text.isEmpty) }
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 7, style: .continuous), focused ? Theme.accent : invalid ? Theme.red : Theme.controlBorder)
        // A ring outside the field: drawn under it, it showed through the translucent dark field and tinted it blue.
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(focused ? Theme.accentSoft : .clear, lineWidth: 3).padding(-3))
        .opacity(isEnabled ? 1 : 0.5)
    }

}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat? = 210
    var height: CGFloat = 34

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text3)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .background(alignment: .leading) { Placeholder(text: placeholder, visible: text.isEmpty) }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: 9, style: .continuous), Theme.controlBorder)
    }
}

/// Placeholder in the mockup's text-3 grey.
private struct Placeholder: View {
    let text: String
    let visible: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text3)
            .lineLimit(1)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FieldError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(Theme.red)
            .padding(.top, 4)
    }
}

// MARK: - Badges and status

/// Small uppercase-free tag such as NFS or FUSE.
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.separator, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize()
    }
}

/// The three states of the mockup plus an error state.
enum StatusKind {
    case on, busy, off, error

    var dot: Color {
        switch self {
        case .on: Theme.green
        case .busy: Theme.orange
        case .off: Theme.text3
        case .error: Theme.red
        }
    }

    var ink: Color {
        switch self {
        case .on: Theme.greenInk
        case .busy: Theme.orangeInk
        case .off: Theme.text2
        case .error: Theme.red
        }
    }

    var soft: Color {
        switch self {
        case .on: Theme.greenSoft
        case .busy: Theme.orangeSoft
        case .off: Theme.separator
        case .error: Theme.redSoft
        }
    }
}

struct StatePill: View {
    let kind: StatusKind
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(kind.dot).frame(width: 8, height: 8)
            Text(label)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(kind.ink)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 23)
        .background(kind.soft, in: Capsule())
        .fixedSize()
    }
}

/// Dot and label without the pill, as in the activity table.
struct StatusLabel: View {
    let kind: StatusKind
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(kind.dot).frame(width: 7, height: 7)
            Text(label).foregroundStyle(kind == .off ? Theme.text2 : kind.dot)
        }
        .lineLimit(1)
    }
}

/// Grey count capsule of the sidebar.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Theme.count, in: Capsule())
    }
}

// MARK: - Tiles, bars and charts

struct ProviderTile: View {
    let provider: Provider
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: (size / 4).rounded(), style: .continuous)
            .fill(provider.color)
            .hairlineBorder(RoundedRectangle(cornerRadius: (size / 4).rounded(), style: .continuous), .white.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                switch provider.glyph {
                case .brand(let name):
                    Image(name).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: size * 0.62, height: size * 0.62)
                case .icon(let name):
                    Image(name).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: size * 0.56, height: size * 0.56)
                }
            }
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

/// Thin progress bar on the separator track.
struct LevelBar: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Theme.separator)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
        }
        .frame(height: height)
    }
}

/// Used space, green until 75 %, orange until 90 %, then red.
struct SpaceBar: View {
    let space: Space?
    var height: CGFloat = 4

    var body: some View {
        LevelBar(fraction: SpaceLevel(space).fraction, color: SpaceLevel(space).color, height: height)
    }
}

struct SpaceLevel {
    let fraction: Double
    let free: Int64?
    let total: Int64?

    init(_ space: Space?) {
        total = space?.total
        free = space?.free ?? space.flatMap { space in space.total.flatMap { total in space.used.map { total - $0 } } }
        if let total, let free, total > 0 {
            fraction = min(1, max(0, Double(total - free) / Double(total)))
        } else {
            fraction = 0
        }
    }

    var isNearlyFull: Bool { fraction >= 0.9 }

    var color: Color {
        fraction >= 0.9 ? Theme.red : fraction >= 0.75 ? Theme.orange : Theme.green
    }
}

/// The last minute of throughput as a line, optionally filled.
/// The top of a throughput scale: the first round value at or above the busiest second, at least 10 Mo/s,
/// so a transfer fills most of the height whatever its speed.
enum ChartScale {
    static func top(_ values: [Double]) -> Double {
        let peak = max(10_000_000, values.max() ?? 0)
        var magnitude = pow(10, log10(peak).rounded(.down))
        while true {
            // Steps whose halves are round too, for the middle tick.
            for step in [1, 1.2, 1.5, 2, 3, 4, 5, 6, 8.0] where step * magnitude >= peak { return step * magnitude }
            magnitude *= 10
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var filled = false

    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            ZStack {
                if filled, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(Theme.accentSoft)
                }
                Path { path in path.addLines(points) }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = ChartScale.top(values)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                    y: size.height - 1 - CGFloat(value / top) * (size.height - 2))
        }
    }
}

// MARK: - Settings layout

struct SectionTitle: View {
    let text: String
    var top: CGFloat = 18

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
            .lineBox(13)
            .padding(.top, top)
            .padding(.bottom, 6)
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// White rounded group whose rows are separated by inset hairlines.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Hairline().padding(.horizontal, 12)
                    }
                    row
                }
            }
        }
        .card()
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var hint: Text?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, hint: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.hint = hint
        self.trailing = trailing()
    }

    init(_ title: String, hint: String?, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, hint: hint.map { Text($0) }, trailing: trailing)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineBox(13)
                if let hint {
                    hint
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineBox(11)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // In a narrow window the text wraps instead of the control being cut.
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

/// Stat tiles on one row, or two rows of two when a tile would be narrower than `minimumWidth`.
/// Each row is as tall as its tallest tile, tiles keep their own height as in an HStack aligned to the top.
struct TileRow: Layout {
    var spacing: CGFloat = 10
    var minimumWidth: CGFloat = 150

    private func columns(_ width: CGFloat, _ count: Int) -> Int {
        guard count > 2 else { return max(count, 1) }
        return width >= minimumWidth * CGFloat(count) + spacing * CGFloat(count - 1) ? count : (count + 1) / 2
    }

    private func grid(_ width: CGFloat, _ subviews: Subviews) -> (columns: Int, tile: CGFloat, rows: [CGFloat]) {
        let columns = columns(width, subviews.count)
        let tile = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tile, height: nil)).height }
        let rows = stride(from: 0, to: heights.count, by: columns).map { heights[$0..<min($0 + columns, heights.count)].max() ?? 0 }
        return (columns, tile, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumWidth * CGFloat(subviews.count)
        let rows = grid(width, subviews).rows
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, tile, rows) = grid(bounds.width, subviews)
        var y = bounds.minY
        for (row, height) in rows.enumerated() {
            for column in 0..<columns where row * columns + column < subviews.count {
                subviews[row * columns + column].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (tile + spacing), y: y),
                                                       proposal: ProposedViewSize(width: tile, height: nil))
            }
            y += height + spacing
        }
    }
}

/// A figure with its label, as in the stat rows of the drive and activity pages.
struct StatTile<Detail: View>: View {
    let label: String
    let value: String
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineBox(11)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .lineBox(17)
                .padding(.top, 2)
                .contentTransition(.numericText())
            detail
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }
}

/// Secondary line under a stat value.
struct StatSub: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text3)
            .lineLimit(1)
            .lineBox(11)
    }
}
