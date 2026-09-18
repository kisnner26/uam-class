#!/usr/bin/env swift
// Genera UAMClass.icns con Core Graphics.
// Uso: swift generate-icon.swift  →  produce UAMClass.icns

import AppKit
import CoreGraphics
import Foundation

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Rounded rect background (grafito con gradient)
    let radius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius,
                        transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient grafito
    let colors = [
        CGColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0),
        CGColor(srgbRed: 0.18, green: 0.18, blue: 0.21, alpha: 1.0)
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray,
                                 locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])
    }

    // Barra vino a la derecha (accent)
    ctx.setFillColor(CGColor(srgbRed: 0.62, green: 0.17, blue: 0.22, alpha: 1.0))
    let barW = s * 0.18
    let barH = s * 0.07
    ctx.fill(CGRect(x: s - barW - s*0.08, y: s*0.08, width: barW, height: barH))

    // Halo vino difuminado detrás de las letras
    let haloColors = [
        CGColor(srgbRed: 0.62, green: 0.17, blue: 0.22, alpha: 0.4),
        CGColor(srgbRed: 0.62, green: 0.17, blue: 0.22, alpha: 0.0)
    ]
    if let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: haloColors as CFArray,
                             locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(halo,
                               startCenter: CGPoint(x: s * 0.35, y: s * 0.6),
                               startRadius: 0,
                               endCenter: CGPoint(x: s * 0.35, y: s * 0.6),
                               endRadius: s * 0.5,
                               options: [])
    }

    ctx.restoreGState()

    // Texto "UC" centrado, blanco, bold
    let text: NSString = "UC"
    let fontSize = s * 0.5
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -fontSize * 0.04
    ]
    let textSize = text.size(withAttributes: attrs)
    let textRect = CGRect(x: (s - textSize.width) / 2,
                          y: (s - textSize.height) / 2 - s * 0.04,
                          width: textSize.width,
                          height: textSize.height)
    text.draw(in: textRect, withAttributes: attrs)

    // Borde muy sutil interior
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(1)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: s-1, height: s-1),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "iconGen", code: 1)
    }
    try data.write(to: url)
}

// Genera el iconset
let fm = FileManager.default
let iconset = URL(fileURLWithPath: "UAMClass.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png",     16),
    ("icon_16x16@2x.png",  32),
    ("icon_32x32.png",     32),
    ("icon_32x32@2x.png",  64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for entry in sizes {
    let img = drawIcon(size: entry.size)
    try savePNG(img, to: iconset.appendingPathComponent(entry.name))
    print("✓ \(entry.name)")
}

// Compilar iconset a icns
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path]
try task.run()
task.waitUntilExit()

print("")
print("✓ UAMClass.icns generado")
