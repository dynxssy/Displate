// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    let inset = size * 0.098 // macOS icon grid: 824pt body on a 1024pt canvas
    let body = NSRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    // Drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Sunrise gradient
    let gradient = NSGradient(colors: [
        NSColor(red: 0.800, green: 0.420, blue: 0.310, alpha: 1),
        NSColor(red: 0.890, green: 0.545, blue: 0.427, alpha: 1),
        NSColor(red: 0.949, green: 0.659, blue: 0.545, alpha: 1),
    ])
    gradient?.draw(in: shape, angle: 90)

    // Soft top highlight
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])
    highlight?.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Sun
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolSize = sun.size
        let rect = NSRect(x: body.midX - symbolSize.width / 2, y: body.midY - symbolSize.height / 2,
                          width: symbolSize.width, height: symbolSize.height)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        glow.shadowBlurRadius = size * 0.02
        glow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        glow.set()
        sun.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    return rep.representation(using: .png, properties: [:])
}

let variants: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]
for (pixels, name) in variants {
    guard let data = render(pixels: pixels) else { fatalError("Failed to render \(name)") }
    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon_\(name).png"))
}
print("Wrote \(output)")
