// Composes the README images from UI snapshots (Tools/Snapshots/render.sh).
// Usage: swift scripts/make-readme-images.swift <snapshots-dir> <language> <output-dir>
import AppKit

let arguments = CommandLine.arguments
let snapshots = URL(fileURLWithPath: arguments[1], isDirectory: true)
let language = arguments[2]
let output = URL(fileURLWithPath: arguments[3], isDirectory: true)

func image(_ name: String) -> NSBitmapImageRep {
    NSBitmapImageRep(data: try! Data(contentsOf: snapshots.appendingPathComponent(name)))!
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws a snapshot (or its top `visibleHeight` pixels) into `rect` on a rounded card with a soft shadow.
func card(_ rep: NSBitmapImageRep, in rect: CGRect, radius: CGFloat, background: NSColor, context: CGContext, visibleHeight: Int? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    background.setFill()
    path.fill()
    context.restoreGState()
    context.saveGState()
    path.addClip()
    // Drawing works in the image's points, not pixels.
    let fraction = CGFloat(visibleHeight ?? rep.pixelsHigh) / CGFloat(rep.pixelsHigh)
    let source = CGRect(x: 0, y: rep.size.height * (1 - fraction), width: rep.size.width, height: rep.size.height * fraction)
    rep.draw(in: rect, from: source, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    context.restoreGState()
}

let canvas = CGSize(width: 2400, height: 1500)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext

let background = NSBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), xRadius: 48, yRadius: 48)
background.addClip()
NSGradient(colors: [color(0xFFC94A), color(0xFF8F5A), color(0xE9508F), color(0x7A4DFF)])!
    .draw(in: CGRect(origin: .zero, size: canvas), angle: -35)

// Settings window on the left, the menu bar panel overlapping on the right, the overlay below.
let settings = image("window-settings-2.png")
// Cut the window below the Large v3 Turbo row so no half-visible row remains.
let settingsVisible = 1236
let settingsHeight: CGFloat = 1180
let settingsSize = CGSize(width: settingsHeight * CGFloat(settings.pixelsWide) / CGFloat(settingsVisible), height: settingsHeight)
card(settings, in: CGRect(origin: CGPoint(x: 140, y: 160), size: settingsSize), radius: 26, background: .white, context: context,
     visibleHeight: settingsVisible)

let panel = image("menu-listening-light.png")
let panelHeight: CGFloat = 1180
let panelSize = CGSize(width: panelHeight * CGFloat(panel.pixelsWide) / CGFloat(panel.pixelsHigh), height: panelHeight)
card(panel, in: CGRect(origin: CGPoint(x: canvas.width - panelSize.width - 150, y: 200), size: panelSize), radius: 30,
     background: color(0xF6F5F8), context: context)

let hud = image("hud-listening.png")
let hudSize = CGSize(width: 840, height: 180)
let hudOrigin = CGPoint(x: (canvas.width - hudSize.width) / 2 - 120, y: 40)
let capsule = CGRect(x: hudOrigin.x + 200, y: hudOrigin.y + 38, width: 460, height: 104)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setFill()
NSBezierPath(roundedRect: capsule, xRadius: 52, yRadius: 52).fill()
context.restoreGState()
hud.draw(in: CGRect(origin: hudOrigin, size: hudSize), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("screenshot-\(language).png"))
print("wrote screenshot-\(language).png")
