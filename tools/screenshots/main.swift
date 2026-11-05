import SwiftUI

// README screenshots: the main window with its title bar buttons and the menu bar panel, light and dark, at 2x,
// with the window's rounded corners and shadow drawn around them. Demo accounts only.
let out = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
NSApplication.shared.setActivationPolicy(.accessory)

func ramp(_ peak: Double, start: Int, stop: Int = 60) -> [Double] {
    (0..<60).map { i in
        guard i >= start, i < stop else { return 0 }
        return min(peak, Double(i - start + 1) * peak / 5) * (0.95 + 0.03 * sin(Double(i) * 0.55) + 0.02 * sin(Double(i) * 1.9 + 1)) * 1e6
    }
}

@MainActor func sample() -> [Drive] {
    func make(_ name: String, _ provider: String, _ account: String, mounted: Bool, read: Double = 0, write: Double = 0,
              used: Double, total: Double, profile: Profile = .documents, fuse: Bool = true, readOnly: Bool = false, cache: Double = 0) -> Drive {
        var record = DriveRecord(remote: name.lowercased(), name: name, provider: provider, account: account)
        record.id = name
        record.settings.profile = profile
        record.settings.method = fuse ? .macFUSE : .nfs
        record.settings.readOnly = readOnly
        record.settings.cacheMaxGB = 20
        let drive = Drive(record: record)
        drive.state = mounted ? .mounted : .unmounted
        drive.readSpeed = read * 1e6
        drive.writeSpeed = write * 1e6
        drive.space = Space(total: Int64(total * 1e12), used: Int64(used * 1e12), free: Int64((total - used) * 1e12))
        drive.cacheBytes = Int64(cache * 1e9)
        if mounted {
            drive.history = read > 0 ? ramp(read, start: 14) : Array(repeating: 0, count: 60)
            drive.writeHistory = write > 0 ? ramp(write, start: 40) : Array(repeating: 0, count: 60)
        }
        return drive
    }
    let drives = [
        make("Médiathèque", "dropbox", "camille@exemple.fr", mounted: true, read: 104, used: 8.54, total: 11, profile: .streaming, readOnly: true),
        make("Google Drive", "gdrive", "camille.martin@exemple.fr", mounted: true, write: 3.2, used: 0.66, total: 2, cache: 1.4),
        make("OneDrive Pro", "onedrive", "c.martin@studio-exemple.fr", mounted: true, read: 18, used: 0.42, total: 1),
        make("Sauvegardes", "s3", "sauvegardes-mac", mounted: false, used: 1.2, total: 10, profile: .backup, fuse: false),
        make("NAS Maison", "synology", "famille", mounted: false, used: 2.4, total: 4, fuse: false)
    ]
    drives[1].uploads = [Upload(name: "Studio/Devis/Devis 2026-11.pdf", bytes: 640_000, size: 1_000_000, speed: 3.2e6)]
    return drives
}

/// Draws a 2x bitmap with rounded corners, a hairline edge and a soft shadow on a transparent canvas.
/// The title bar buttons of an inactive offscreen window are grey; they are painted in their active colors.
struct Light { let rect: CGRect; let fill: CGColor; let edge: CGColor }

@MainActor func framed(_ rep: NSBitmapImageRep, radius: CGFloat, dark: Bool, lights: [Light] = []) -> Data {
    let scale: CGFloat = 2, margin: CGFloat = 56 * scale
    let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
    let canvas = CGSize(width: w + margin * 2, height: h + margin * 2)
    let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: margin, y: margin + 10 * scale, width: w, height: h)
    let path = CGPath(roundedRect: rect, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 46 * scale, color: CGColor(gray: 0, alpha: dark ? 0.55 : 0.32))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: dark ? 0.15 : 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.draw(rep.cgImage!, in: rect)
    for light in lights {
        let circle = CGRect(x: rect.minX + light.rect.minX * scale, y: rect.minY + light.rect.minY * scale,
                            width: light.rect.width * scale, height: light.rect.height * scale)
        ctx.setFillColor(light.fill); ctx.fillEllipse(in: circle)
        ctx.setStrokeColor(light.edge); ctx.setLineWidth(0.5 * scale); ctx.strokeEllipse(in: circle.insetBy(dx: 0.25 * scale, dy: 0.25 * scale))
    }
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5 * scale, dy: 0.5 * scale), cornerWidth: radius * scale - 0.5 * scale,
                       cornerHeight: radius * scale - 0.5 * scale, transform: nil))
    ctx.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.18 : 0.16)); ctx.setLineWidth(1 * scale); ctx.strokePath()
    let image = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

@MainActor func bitmap(_ view: NSView, _ size: CGSize) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    view.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
    return rep
}

@MainActor func window(_ name: String, size: CGSize, setup: (AppState) -> Void) {
    for dark in [false, true] {
        let store = DriveStore(showing: sample(), preferences: Preferences(defaults: UserDefaults(suiteName: "readme-snap")!), engineVersion: "1.75.2-docklume.8")
        let app = AppState()
        setup(app)
        let host = NSHostingView(rootView: MainWindow().environment(store).environment(app).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let frame = window.contentView!.superview!
        let colors: [(NSWindow.ButtonType, Int, Int)] = [(.closeButton, 0xFF5F57, 0xE2463F), (.miniaturizeButton, 0xFEBC2E, 0xE1A325), (.zoomButton, 0x28C840, 0x14AE2C)]
        let lights = colors.compactMap { type, fill, edge -> Light? in
            guard let button = window.standardWindowButton(type) else { return nil }
            var box = button.convert(button.bounds, to: frame)
            if frame.isFlipped { box.origin.y = frame.bounds.height - box.maxY }
            let side = min(box.width, box.height)
            let circle = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
            func color(_ hex: Int) -> CGColor { CGColor(srgbRed: CGFloat(hex >> 16) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) }
            return Light(rect: circle, fill: color(fill), edge: color(edge))
        }
        let data = framed(bitmap(frame, frame.bounds.size), radius: 16, dark: dark, lights: lights)
        try! data.write(to: out.appending(path: "\(name)-\(dark ? "dark" : "light").png"))
    }
}

@MainActor func panel() {
    for dark in [false, true] {
        let store = DriveStore(showing: sample(), preferences: Preferences(defaults: UserDefaults(suiteName: "readme-snap")!), engineVersion: "1.75.2-docklume.8")
        let host = NSHostingView(rootView: MenuBarPanel().environment(store).environment(AppState()).frame(width: 344).fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.95, alpha: 1))))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let data = framed(bitmap(host, host.bounds.size), radius: 14, dark: dark)
        try! data.write(to: out.appending(path: "panel-\(dark ? "dark" : "light").png"))
    }
}

MainActor.assumeIsolated {
    let size = CGSize(width: 1120, height: 720)
    window("drives", size: size) { $0.page = .drives }
    window("detail", size: size) { $0.page = .drive("Médiathèque") }
    window("activity", size: size) { $0.page = .activity }
    window("add", size: size) { $0.overlay = .add(provider: "dropbox") }
    panel()
}
