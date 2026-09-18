import AppKit
import CoreGraphics
import Foundation

// Convierte una imagen cuadrada (el arte que devuelve un generador de imágenes)
// en un .icns válido para macOS.
//
// Hace tres cosas que un simple `sips` no hace y que son las que separan un
// ícono que se ve nativo de uno que se ve pegado:
//
//  1. Respeta la grilla de iconos de macOS: sobre un lienzo de 1024 el mosaico
//     ocupa 824×824 centrado. Si el arte va a sangre, el ícono se ve más grande
//     que todos los demás del Dock.
//  2. Recorta con esquina de curvatura continua (el "squircle" de Apple), no con
//     un arco de círculo. La diferencia se nota a tamaño Dock.
//  3. Genera las diez variantes que pide iconutil.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandler.fail("""
    Uso: make-icon <arte.png> [salida.icns]

      arte.png     Imagen cuadrada, idealmente 1024×1024 o más.
      salida.icns  Por defecto: UAMClass.icns
    """)
}

let inputPath = args[1]
let outputPath = args.count >= 3 ? args[2] : "UAMClass.icns"

enum FileHandler {
    static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        exit(1)
    }
}

guard let source = NSImage(contentsOfFile: inputPath) else {
    FileHandler.fail("No se pudo leer la imagen: \(inputPath)")
}

// MARK: - Squircle

/// Rectángulo redondeado de curvatura continua.
///
/// La esquina de Apple no es un cuarto de círculo: la curvatura entra y sale de
/// forma gradual. Se aproxima con cúbicas cuyos puntos de control se estiran
/// ~1.528 veces el radio, que es la constante que usa el sistema.
func continuousRoundedRect(in rect: CGRect, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k: CGFloat = 1.528665
    let c = min(r * k, min(rect.width, rect.height) / 2)
    let (minX, minY) = (rect.minX, rect.minY)
    let (maxX, maxY) = (rect.maxX, rect.maxY)

    path.move(to: CGPoint(x: minX + c, y: minY))
    path.addLine(to: CGPoint(x: maxX - c, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + c),
                  control1: CGPoint(x: maxX - c * 0.33, y: minY),
                  control2: CGPoint(x: maxX, y: minY + c * 0.33))
    path.addLine(to: CGPoint(x: maxX, y: maxY - c))
    path.addCurve(to: CGPoint(x: maxX - c, y: maxY),
                  control1: CGPoint(x: maxX, y: maxY - c * 0.33),
                  control2: CGPoint(x: maxX - c * 0.33, y: maxY))
    path.addLine(to: CGPoint(x: minX + c, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - c),
                  control1: CGPoint(x: minX + c * 0.33, y: maxY),
                  control2: CGPoint(x: minX, y: maxY - c * 0.33))
    path.addLine(to: CGPoint(x: minX, y: minY + c))
    path.addCurve(to: CGPoint(x: minX + c, y: minY),
                  control1: CGPoint(x: minX, y: minY + c * 0.33),
                  control2: CGPoint(x: minX + c * 0.33, y: minY))
    path.closeSubpath()
    return path
}

// MARK: - Render

/// Dibuja el arte dentro del mosaico, a la escala pedida.
func renderTile(side: Int) -> Data? {
    let s = CGFloat(side)
    // Proporciones oficiales de la grilla macOS: 824 de mosaico en 1024 de lienzo.
    let tile = s * (824.0 / 1024.0)
    let inset = (s - tile) / 2
    let radius = tile * (185.4 / 824.0)

    guard let ctx = CGContext(data: nil,
                              width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let tileRect = CGRect(x: inset, y: inset, width: tile, height: tile)

    // Sombra de contacto, como la que llevan los iconos del sistema.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -tile * 0.012),
                  blur: tile * 0.035,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(continuousRoundedRect(in: tileRect, radius: radius))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // El arte, recortado al mosaico.
    ctx.saveGState()
    ctx.addPath(continuousRoundedRect(in: tileRect, radius: radius))
    ctx.clip()

    var proposed = tileRect
    if let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
        // aspectFill: nunca deforma el arte.
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let scale = max(tile / iw, tile / ih)
        let dw = iw * scale, dh = ih * scale
        ctx.draw(cg, in: CGRect(x: tileRect.midX - dw / 2,
                                y: tileRect.midY - dh / 2,
                                width: dw, height: dh))
    }
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Iconset

let fm = FileManager.default
let iconsetURL = URL(fileURLWithPath: "UAMClass.iconset")
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024)
]

for (name, side) in variants {
    guard let data = renderTile(side: side) else {
        FileHandler.fail("Falló el render de \(name)")
    }
    try data.write(to: iconsetURL.appendingPathComponent(name))
    print("  ✓ \(name)")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", outputPath]
try task.run()
task.waitUntilExit()

guard task.terminationStatus == 0 else {
    FileHandler.fail("iconutil falló")
}

print("\n✓ \(outputPath) listo. Ahora corré ./build-app.sh")
