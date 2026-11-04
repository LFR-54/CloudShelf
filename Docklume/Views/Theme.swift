import SwiftUI

/// The mockup's CSS variables, light and dark.
enum Theme {
    static let accent = Color(0x007AFF, dark: 0x0A84FF)
    static let accentSoft = Color(0x007AFF, 0.14, dark: 0x0A84FF, 0.24)
    static let accentNav = Color(0x007AFF, 0.12, dark: 0x0A84FF, 0.22)
    static let green = Color(0x28CD41, dark: 0x30D158)
    static let orange = Color(0xFF9500, dark: 0xFF9F0A)
    static let red = Color(0xFF3B30, dark: 0xFF453A)
    static let teal = Color(0x30B0C7, dark: 0x40C8E0)
    /// Write throughput in charts, beside accent for reads; checked apart from it for colour-blind readers.
    static let upload = Color(0x1A9CB4, dark: 0x2BA5AE)
    static let gray = Color(0x8E8E93, dark: 0x98989D)
    static let cardSolid = Color(0xFFFFFF, dark: 0x2B2B2E)
    static let greenInk = Color(0x248A3D, dark: 0x30D158)
    static let greenSoft = Color(0x28CD41, 0.15, dark: 0x30D158, 0.16)
    static let orangeInk = Color(0xB25000, dark: 0xFF9F0A)
    static let orangeSoft = Color(0xFF9500, 0.16, dark: 0xFF9F0A, 0.16)
    static let redSoft = Color(0xFF3B30, 0.13, dark: 0xFF453A, 0.18)
    static let inset = Color(0x000000, 0.035, dark: 0xFFFFFF, 0.05)
    static let window = Color(0xF0F0F4, dark: 0x1E1E20)
    static let sidebar = Color(0xE4E4EA, 0.72, dark: 0x2E2E32, 0.66)
    static let card = Color(0xFFFFFF, dark: 0xFFFFFF, 0.055)
    /// Behind a service's logo: white, a shade softer in dark mode where pure white glares. Any greyer and the
    /// logos look faded.
    static let logoTile = Color(0xFFFFFF, dark: 0xF5F5F7)
    static let cardBorder = Color(0x000000, 0.07, dark: 0xFFFFFF, 0.07)
    static let separator = Color(0x000000, 0.08, dark: 0xFFFFFF, 0.09)
    static let grid = Color(0x000000, 0.06, dark: 0xFFFFFF, 0.07)
    static let hover = Color(0x000000, 0.05, dark: 0xFFFFFF, 0.06)
    static let text = Color(0x1D1D1F, dark: 0xF5F5F7)
    static let text2 = Color(0x1D1D1F, 0.62, dark: 0xF5F5F7, 0.62)
    static let text3 = Color(0x1D1D1F, 0.42, dark: 0xF5F5F7, 0.40)
    static let control = Color(0xFFFFFF, dark: 0xFFFFFF, 0.09)
    static let controlBorder = Color(0x000000, 0.13, dark: 0xFFFFFF, 0.13)
    static let field = Color(0xFFFFFF, dark: 0xFFFFFF, 0.06)
    static let tooltip = Color(0xFFFFFF, 0.97, dark: 0x2C2C30, 0.97)
    static let scrim = Color(0x000000, 0.16, dark: 0x000000, 0.40)
    static let segmentOn = Color(0xFFFFFF, dark: 0xFFFFFF, 0.18)
    static let count = Color(0x787880, 0.55, dark: 0x787880, 0.55)
    static let security = Color(0x1E8E4E, dark: 0x1E8E4E)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// A color with its light and dark values.
    init(_ light: UInt32, _ lightAlpha: Double = 1, dark: UInt32, _ darkAlpha: Double = 1) {
        func color(_ hex: UInt32, _ alpha: Double) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        let light = color(light, lightAlpha), dark = color(dark, darkAlpha)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension EnvironmentValues {
    /// Set when the window is narrower than the mockup's 1000 pt: headers show icons only, cards and tiles tighten.
    @Entry var compactLayout = false
    /// The room a dialog has inside the window.
    @Entry var dialogSpace = CGSize(width: CGFloat.infinity, height: .infinity)
}

extension View {
    /// The CSS line box: SF Pro's natural line is 1.19 em, the mockup sets 1.4 em; the difference goes between lines
    /// and, halved, above and below.
    func lineBox(_ size: CGFloat, _ lineHeight: CGFloat = 1.4) -> some View {
        lineSpacing(max(0, (lineHeight - 1.193) * size))
            .padding(.vertical, max(0, (lineHeight - 1.193) * size / 2))
    }

    /// A one-pixel border, sharp on any screen.
    func hairlineBorder<S: InsettableShape, Style: ShapeStyle>(_ shape: S, _ style: Style) -> some View {
        modifier(HairlineBorder(shape: shape, style: style))
    }

    /// Card surface with its hairline border.
    func card(radius: CGFloat = 12, fill: Color = Theme.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .hairlineBorder(RoundedRectangle(cornerRadius: radius, style: .continuous), Theme.cardBorder)
    }

    /// A control surface: fill, hairline border and the mockup's one-pixel shadow.
    func control(radius: CGFloat, fill: Color = Theme.control, border: Color = Theme.controlBorder) -> some View {
        modifier(ControlSurface(radius: radius, fill: fill, border: border))
    }
}

/// The mockup's hairlines are one device pixel: half a point on Retina. On a 1x screen half a point is drawn
/// as a blurred, half-strength pixel that comes and goes along a border, so lines take one pixel at any scale.
private struct HairlineBorder<S: InsettableShape, Style: ShapeStyle>: ViewModifier {
    @Environment(\.displayScale) private var scale
    let shape: S
    let style: Style

    func body(content: Content) -> some View {
        content.overlay(shape.strokeBorder(style, lineWidth: 1 / scale))
    }
}

private struct ControlSurface: ViewModifier {
    @Environment(\.displayScale) private var scale
    let radius: CGFloat
    let fill: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .hairlineBorder(RoundedRectangle(cornerRadius: radius, style: .continuous), border)
            .shadow(color: .black.opacity(0.06), radius: 1 / scale, y: 1 / scale)
    }
}

/// A horizontal one-pixel line, as between the rows of a group.
struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var color: Color = Theme.separator

    var body: some View {
        Rectangle().fill(color).frame(height: 1 / scale)
    }
}
