// Generates the macOS AppIcon image set for CrossPost: a purple→blue gradient
// squircle (blending the Mastodon and Bluesky brand colors) with a white
// double-speech-bubble glyph.
//
// Usage: swift scripts/make_app_icon.swift [output.appiconset dir]
import AppKit

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/App/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
let mastodonPurple = srgb(99, 100, 255)   // ~#6364FF
let blueskyBlue = srgb(17, 133, 254)      // ~#1185FE

func renderIcon(_ n: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(n), pixelsHigh: Int(n),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: n, height: n))

    // Rounded tile with a small transparent margin (macOS draws its own shape).
    let inset = n * 0.085
    let tile = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
    let radius = tile.width * 0.2237   // Apple's continuous-corner ratio
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).addClip()
    NSGradient(colors: [mastodonPurple, blueskyBlue])!.draw(in: tile, angle: -45)
    NSGraphicsContext.restoreGraphicsState()

    // White double-speech-bubble glyph, centered.
    let config = NSImage.SymbolConfiguration(pointSize: n * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let base = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil),
       let glyph = base.withSymbolConfiguration(config) {
        let s = glyph.size
        glyph.draw(in: CGRect(x: (n - s.width) / 2, y: (n - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = renderIcon(CGFloat(px))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(px)\n".utf8))
        continue
    }
    let path = "\(outDir)/icon_\(px).png"
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
