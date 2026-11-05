import AppKit
// For each pair of PNGs: same size?, and the bounding box of the pixels that differ (in points, at 2x).
func pixels(_ url: URL) -> (Int, Int, [UInt8]) {
    let image = NSBitmapImageRep(data: try! Data(contentsOf: url))!.cgImage!
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, data)
}
let old = URL(filePath: CommandLine.arguments[1]), new = URL(filePath: CommandLine.arguments[2])
for name in try! FileManager.default.contentsOfDirectory(atPath: new.path).sorted() where name.hasSuffix(".png") {
    let (w1, h1, a) = pixels(old.appending(path: name)), (w2, h2, b) = pixels(new.appending(path: name))
    guard w1 == w2, h1 == h2 else { print("\(name): taille \(w1)×\(h1) → \(w2)×\(h2)"); continue }
    var minX = w1, minY = h1, maxX = -1, maxY = -1, count = 0
    for y in 0..<h1 { for x in 0..<w1 {
        let i = (y * w1 + x) * 4
        if abs(Int(a[i]) - Int(b[i])) > 2 || abs(Int(a[i+1]) - Int(b[i+1])) > 2 || abs(Int(a[i+2]) - Int(b[i+2])) > 2 {
            count += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    } }
    print(count == 0 ? "\(name): identique" : "\(name): \(count) px changés, zone \(minX),\(minY) → \(maxX),\(maxY)")
}
