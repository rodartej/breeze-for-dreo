// Draws the app icon (white fan on a blue gradient) into Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Four swept blades, drawn by hand: Apple's license doesn't allow SF Symbols in app icons.
/// Same geometry as `FanBlades` in Sources/Views.swift.
func bladesPath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    let c = NSPoint(x: rect.midX, y: rect.midY), r = rect.width / 2
    func p(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat) -> NSPoint {
        NSPoint(x: c.x + r * (x * cos(a) - y * sin(a)), y: c.y + r * (x * sin(a) + y * cos(a)))
    }
    for i in 0..<4 {
        let a = CGFloat(i) * .pi / 2
        path.move(to: p(0.10, 0.10, a))
        path.curve(to: p(0.88, 0.30, a), controlPoint1: p(0.18, 0.62, a), controlPoint2: p(0.70, 0.66, a))
        path.curve(to: p(0.14, -0.08, a), controlPoint1: p(1.02, 0.04, a), controlPoint2: p(0.62, -0.20, a))
        path.close()
    }
    return path
}

func draw(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.78, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.90, alpha: 1))!.draw(in: path, angle: -90)
    NSColor.white.setFill()
    bladesPath(in: NSRect(x: s * 0.23, y: s * 0.23, width: s * 0.54, height: s * 0.54)).fill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.445, y: s * 0.445, width: s * 0.11, height: s * 0.11)).fill()  // hub
    NSColor(srgbRed: 0.14, green: 0.55, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.47, y: s * 0.47, width: s * 0.06, height: s * 0.06)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
