// Renders Canto's app icon: a toucan singing lines of text on a tropical gradient.
// Usage: swift scripts/make-icon.swift Canto/Resources/Assets.xcassets/AppIcon.appiconset [preview.png]
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

func drawIcon(in context: CGContext) {
    // macOS icon grid: an 824 pt rounded square centered in 1024, with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    color(0x000000).setFill()
    squircle.fill()
    context.restoreGState()

    context.saveGState()
    squircle.addClip()

    // Tropical sky: warm mango at the top melting into lagoon turquoise.
    NSGradient(colors: [color(0xFFC94A), color(0xFF8F5A), color(0xE9508F), color(0x7A4DFF)])!
        .draw(in: body, angle: -90)

    // Sun glow behind the bird.
    NSGradient(colors: [color(0xFFF3B0, 0.75), color(0xFFF3B0, 0)])!
        .draw(in: ellipse(430, 640, 330, 330), relativeCenterPosition: .zero)

    // Jungle leaves in the corners.
    func leaf(center: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat, fill: NSColor) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle * .pi / 180)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: -length / 2, y: 0))
        path.curve(to: CGPoint(x: length / 2, y: 0), controlPoint1: CGPoint(x: -length / 4, y: width), controlPoint2: CGPoint(x: length / 4, y: width))
        path.curve(to: CGPoint(x: -length / 2, y: 0), controlPoint1: CGPoint(x: length / 4, y: -width), controlPoint2: CGPoint(x: -length / 4, y: -width))
        fill.setFill()
        path.fill()
        let vein = NSBezierPath()
        vein.move(to: CGPoint(x: -length / 2 + 20, y: 0))
        vein.line(to: CGPoint(x: length / 2 - 30, y: 0))
        vein.lineWidth = 7
        color(0xFFFFFF, 0.18).setStroke()
        vein.stroke()
        context.restoreGState()
    }
    leaf(center: CGPoint(x: 170, y: 250), length: 420, width: 110, angle: 60, fill: color(0x1FA37A))
    leaf(center: CGPoint(x: 290, y: 150), length: 380, width: 95, angle: 20, fill: color(0x14805F))

    // Branch.
    let branch = NSBezierPath()
    branch.move(to: CGPoint(x: 80, y: 305))
    branch.curve(to: CGPoint(x: 700, y: 270), controlPoint1: CGPoint(x: 300, y: 330), controlPoint2: CGPoint(x: 520, y: 250))
    branch.lineWidth = 34
    branch.lineCapStyle = .round
    color(0x6B3E26).setStroke()
    branch.stroke()

    // Tail and body.
    let tail = NSBezierPath(roundedRect: CGRect(x: 250, y: 150, width: 95, height: 220), xRadius: 45, yRadius: 45)
    color(0x1B1B2A).setFill()
    context.saveGState()
    context.translateBy(x: 300, y: 260)
    context.rotate(by: 0.35)
    context.translateBy(x: -300, y: -260)
    tail.fill()
    context.restoreGState()

    let ink = color(0x1B1B2A)
    ink.setFill()
    ellipse(385, 440, 165, 200).fill()          // body
    ellipse(425, 600, 150, 140).fill()          // head

    // Yellow bib.
    color(0xFFD84A).setFill()
    ellipse(470, 540, 105, 95).fill()
    color(0xFF9F2E).setFill()
    ellipse(455, 455, 80, 30).fill()            // orange band under the bib

    // Wing.
    let wing = NSBezierPath()
    wing.move(to: CGPoint(x: 290, y: 560))
    wing.curve(to: CGPoint(x: 330, y: 290), controlPoint1: CGPoint(x: 230, y: 470), controlPoint2: CGPoint(x: 260, y: 330))
    wing.curve(to: CGPoint(x: 400, y: 520), controlPoint1: CGPoint(x: 390, y: 360), controlPoint2: CGPoint(x: 420, y: 450))
    wing.close()
    color(0x2C2C44).setFill()
    wing.fill()

    // Feet on the branch.
    color(0x5AA9FF).setFill()
    ellipse(360, 290, 34, 18).fill()
    ellipse(440, 286, 34, 18).fill()

    // Beak: a big open banana beak.
    let upper = NSBezierPath()
    upper.move(to: CGPoint(x: 520, y: 690))
    upper.curve(to: CGPoint(x: 880, y: 600), controlPoint1: CGPoint(x: 660, y: 760), controlPoint2: CGPoint(x: 830, y: 700))
    upper.curve(to: CGPoint(x: 540, y: 612), controlPoint1: CGPoint(x: 770, y: 610), controlPoint2: CGPoint(x: 640, y: 600))
    upper.close()
    context.saveGState()
    upper.addClip()
    NSGradient(colors: [color(0x3FD17F), color(0xFFD23F), color(0xFF7A1A), color(0xE8344E)])!
        .draw(in: CGRect(x: 520, y: 590, width: 370, height: 180), angle: 0)
    context.restoreGState()

    let lower = NSBezierPath()
    lower.move(to: CGPoint(x: 545, y: 590))
    lower.curve(to: CGPoint(x: 800, y: 520), controlPoint1: CGPoint(x: 660, y: 585), controlPoint2: CGPoint(x: 760, y: 560))
    lower.curve(to: CGPoint(x: 550, y: 548), controlPoint1: CGPoint(x: 720, y: 520), controlPoint2: CGPoint(x: 620, y: 530))
    lower.close()
    context.saveGState()
    lower.addClip()
    NSGradient(colors: [color(0xFFD23F), color(0xFF7A1A), color(0xE8344E)])!
        .draw(in: CGRect(x: 540, y: 510, width: 270, height: 90), angle: 0)
    context.restoreGState()

    // Eye with a blue ring.
    color(0x3BA8FF).setFill()
    ellipse(468, 652, 46, 46).fill()
    color(0xFFFFFF).setFill()
    ellipse(472, 654, 28, 28).fill()
    ink.setFill()
    ellipse(480, 654, 16, 16).fill()
    color(0xFFFFFF).setFill()
    ellipse(485, 660, 5, 5).fill()

    // Song turning into lines of text, flying out of the beak.
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    color(0xFFFFFF).setFill()
    let lines: [(x: CGFloat, y: CGFloat, width: CGFloat)] = [(700, 470, 190), (660, 400, 230), (700, 330, 150)]
    for line in lines {
        NSBezierPath(roundedRect: CGRect(x: line.x, y: line.y - 22, width: line.width, height: 44), xRadius: 22, yRadius: 22).fill()
    }
    // A music note above the beak.
    ellipse(790, 760, 30, 24).fill()
    NSBezierPath(roundedRect: CGRect(x: 808, y: 760, width: 14, height: 120), xRadius: 7, yRadius: 7).fill()
    let flag = NSBezierPath()
    flag.move(to: CGPoint(x: 816, y: 880))
    flag.curve(to: CGPoint(x: 870, y: 810), controlPoint1: CGPoint(x: 870, y: 870), controlPoint2: CGPoint(x: 880, y: 840))
    flag.line(to: CGPoint(x: 816, y: 840))
    flag.close()
    flag.fill()

    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.count > 2 {
    try render(pixels: 512).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons")
