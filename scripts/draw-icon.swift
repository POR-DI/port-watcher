import AppKit

// Usage: swift draw-icon.swift <variant 1|2|3> <output.png> [size=1024]
let variant = Int(CommandLine.arguments[1]) ?? 1
let output = CommandLine.arguments[2]
let size = CGFloat(Int(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "1024") ?? 1024)

// Draw into an explicit bitmap so the pixel size is exact (lockFocus would render at the screen's 2x scale).
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext
let s = size / 1024  // design in 1024 units

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// macOS icon: rounded square inset ~10% with a subtle vertical gradient.
let inset = 100 * s
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
ctx.addPath(rounded(tile, 185 * s))
ctx.clip()

let colors: [CGColor]
switch variant {
case 1: colors = [NSColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1).cgColor,
                  NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1).cgColor]
case 2: colors = [NSColor(red: 0.10, green: 0.55, blue: 0.62, alpha: 1).cgColor,
                  NSColor(red: 0.04, green: 0.28, blue: 0.38, alpha: 1).cgColor]
default: colors = [NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1).cgColor,
                   NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1).cgColor]
}
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let accent = NSColor(red: 0.20, green: 0.85, blue: 0.55, alpha: 1).cgColor   // "LISTEN" green
let ink: CGColor = variant == 3 ? NSColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1).cgColor
                                : NSColor.white.cgColor

let center = CGPoint(x: size / 2, y: size / 2)

switch variant {
case 1:
    // Ethernet-jack glyph: a socket outline with a green "live" dot.
    let jack = CGRect(x: 262 * s, y: 300 * s, width: 500 * s, height: 400 * s)
    ctx.setStrokeColor(ink); ctx.setLineWidth(46 * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: jack.minX, y: jack.maxY))
    path.addLine(to: CGPoint(x: jack.maxX, y: jack.maxY))
    path.addLine(to: CGPoint(x: jack.maxX, y: jack.minY + 140 * s))
    path.addLine(to: CGPoint(x: jack.maxX - 90 * s, y: jack.minY + 140 * s))
    path.addLine(to: CGPoint(x: jack.maxX - 90 * s, y: jack.minY + 60 * s))
    path.addLine(to: CGPoint(x: jack.maxX - 160 * s, y: jack.minY + 60 * s))
    path.addLine(to: CGPoint(x: jack.maxX - 160 * s, y: jack.minY))
    path.addLine(to: CGPoint(x: jack.minX + 160 * s, y: jack.minY))
    path.addLine(to: CGPoint(x: jack.minX + 160 * s, y: jack.minY + 60 * s))
    path.addLine(to: CGPoint(x: jack.minX + 90 * s, y: jack.minY + 60 * s))
    path.addLine(to: CGPoint(x: jack.minX + 90 * s, y: jack.minY + 140 * s))
    path.addLine(to: CGPoint(x: jack.minX, y: jack.minY + 140 * s))
    path.closeSubpath()
    ctx.addPath(path); ctx.strokePath()
    // pins
    ctx.setLineWidth(28 * s)
    for i in 0..<6 {
        let x = jack.minX + 120 * s + CGFloat(i) * 52 * s
        ctx.move(to: CGPoint(x: x, y: jack.maxY - 60 * s))
        ctx.addLine(to: CGPoint(x: x, y: jack.maxY - 190 * s))
    }
    ctx.strokePath()
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: 748 * s, y: 748 * s, width: 120 * s, height: 120 * s))

case 2:
    // Radar: concentric arcs around a listening dot.
    ctx.setStrokeColor(ink); ctx.setLineCap(.round)
    for (i, r) in [150, 260, 370].enumerated() {
        ctx.setLineWidth((44 - CGFloat(i) * 6) * s)
        ctx.addArc(center: center, radius: CGFloat(r) * s, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
        ctx.strokePath()
    }
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: center.x - 70 * s, y: center.y - 70 * s, width: 140 * s, height: 140 * s))

default:
    // Port number badge: a plug-style "P" made of a bold rounded rect + green cable dot.
    ctx.setStrokeColor(ink); ctx.setLineWidth(56 * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 330 * s, y: 250 * s))
    p.addLine(to: CGPoint(x: 330 * s, y: 760 * s))
    p.addLine(to: CGPoint(x: 560 * s, y: 760 * s))
    p.addArc(center: CGPoint(x: 560 * s, y: 620 * s), radius: 140 * s, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    p.addLine(to: CGPoint(x: 330 * s, y: 480 * s))
    ctx.addPath(p); ctx.strokePath()
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: 640 * s, y: 250 * s, width: 130 * s, height: 130 * s))
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: output))
