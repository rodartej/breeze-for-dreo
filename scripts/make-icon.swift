// Draws the app icon (white fan on a blue gradient) into Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

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
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .regular)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    let fan = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    fan.draw(in: NSRect(x: (s - fan.size.width) / 2, y: (s - fan.size.height) / 2,
                        width: fan.size.width, height: fan.size.height))
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
