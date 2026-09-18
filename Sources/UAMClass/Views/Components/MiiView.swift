import SwiftUI

/// Dibuja un `Mii`. Todo pasa por un `Canvas` sobre un lienzo fijo de 100×100
/// que después se escala: así el mismo código sirve para un avatar de 22 puntos
/// en un foro y para el retrato de 160 del editor, sin pixelarse ni tener que
/// mantener dos versiones de cada forma.
struct MiiView: View {
    let mii: Mii
    var size: CGFloat = 64
    var showBackground: Bool = true

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 100
            ctx.scaleBy(x: s, y: s)
            MiiRenderer.draw(mii, into: &ctx, background: showBackground)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Renderer

enum MiiRenderer {

    static func draw(_ m: Mii, into ctx: inout GraphicsContext, background: Bool) {
        let skin = MiiCatalog.skins[safe: m.skin] ?? .gray
        let hairC = MiiCatalog.hairColors[safe: m.hairColor] ?? .black

        if background {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)),
                     with: .color(MiiCatalog.backgrounds[safe: m.background] ?? .gray))
        }

        // El pelo largo va DEBAJO de la cabeza: si no, la melena tapa la cara.
        drawHairBack(m.hair, ctx: &ctx, color: hairC)

        // Orejas antes que la cara para que queden pegadas al costado.
        let face = faceRect(m.face)
        for side in [-1.0, 1.0] {
            let ex = 50 + side * (face.width / 2 - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: ex - 5, y: 48, width: 10, height: 13)),
                     with: .color(skin))
        }

        ctx.fill(facePath(m.face), with: .color(skin))
        // Sombra bajo el mentón: sin esto la cara se ve plana como una calcomanía.
        ctx.fill(chinShade(m.face), with: .color(.black.opacity(0.05)))

        drawBrows(m, ctx: &ctx)
        drawEyes(m, ctx: &ctx)
        drawNose(m, ctx: &ctx, skin: skin)
        drawMouth(m, ctx: &ctx)
        drawBeard(m, ctx: &ctx, color: hairC)
        drawHairFront(m.hair, ctx: &ctx, color: hairC, face: face)
        drawGlasses(m, ctx: &ctx)
    }

    // MARK: Cara

    /// Cada forma es (ancho, alto, ancho de mentón). El mentón es lo que más
    /// cambia la percepción del rostro, más que el ancho total.
    private static func faceMetrics(_ style: Int) -> (w: Double, h: Double, chin: Double) {
        switch style {
        case 1:  return (46, 58, 0.62)   // ovalada
        case 2:  return (50, 54, 0.92)   // cuadrada
        case 3:  return (50, 56, 0.42)   // corazón
        case 4:  return (42, 62, 0.66)   // alargada
        case 5:  return (48, 56, 0.34)   // angulosa
        default: return (48, 54, 0.78)   // redonda
        }
    }

    private static func faceRect(_ style: Int) -> CGRect {
        let m = faceMetrics(style)
        return CGRect(x: 50 - m.w / 2, y: 26, width: m.w, height: m.h)
    }

    private static func facePath(_ style: Int) -> Path {
        let m = faceMetrics(style)
        let r = faceRect(style)
        let cx = r.midX
        let chinW = m.w * m.chin

        var p = Path()
        p.move(to: CGPoint(x: cx, y: r.minY))
        // Sien derecha
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.36),
                       control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.06))
        // Mejilla derecha hacia el mentón
        p.addQuadCurve(to: CGPoint(x: cx + chinW / 2, y: r.maxY - r.height * 0.10),
                       control: CGPoint(x: r.maxX - r.width * 0.02, y: r.minY + r.height * 0.74))
        // Mentón
        p.addQuadCurve(to: CGPoint(x: cx - chinW / 2, y: r.maxY - r.height * 0.10),
                       control: CGPoint(x: cx, y: r.maxY + r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.36),
                       control: CGPoint(x: r.minX + r.width * 0.02, y: r.minY + r.height * 0.74))
        p.addQuadCurve(to: CGPoint(x: cx, y: r.minY),
                       control: CGPoint(x: r.minX, y: r.minY + r.height * 0.06))
        p.closeSubpath()
        return p
    }

    private static func chinShade(_ style: Int) -> Path {
        let r = faceRect(style)
        var p = Path()
        p.addEllipse(in: CGRect(x: r.midX - r.width * 0.22, y: r.maxY - r.height * 0.20,
                                width: r.width * 0.44, height: r.height * 0.14))
        return p
    }

    // MARK: Ojos

    private static func eyeCenters(_ m: Mii) -> (CGPoint, CGPoint) {
        let dx = 10 + m.eyeSpacing * 8      // 10…18 desde el centro
        let y  = 50 + (m.eyeLevel - 0.5) * 10
        return (CGPoint(x: 50 - dx, y: y), CGPoint(x: 50 + dx, y: y))
    }

    private static func drawEyes(_ m: Mii, ctx: inout GraphicsContext) {
        let (l, r) = eyeCenters(m)
        let iris = MiiCatalog.eyeColors[safe: m.eyeColor] ?? .black
        for (c, mirror) in [(l, -1.0), (r, 1.0)] {
            drawEye(m.eyes, at: c, mirror: mirror, iris: iris, ctx: &ctx)
        }
    }

    private static func drawEye(_ style: Int, at c: CGPoint, mirror: Double,
                                iris: Color, ctx: inout GraphicsContext) {
        let ink = Color(.sRGB, red: 0.12, green: 0.10, blue: 0.08, opacity: 1)

        // Los estilos "cerrados" son solo un trazo: no llevan blanco ni pupila.
        switch style {
        case 4: // contentos: ^ ^
            var p = Path()
            p.move(to: CGPoint(x: c.x - 5, y: c.y + 2))
            p.addQuadCurve(to: CGPoint(x: c.x + 5, y: c.y + 2),
                           control: CGPoint(x: c.x, y: c.y - 5))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2, lineCap: .round))
            return
        case 5: // dormidos: línea recta
            var p = Path()
            p.move(to: CGPoint(x: c.x - 5, y: c.y))
            p.addLine(to: CGPoint(x: c.x + 5, y: c.y))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 1.8, lineCap: .round))
            return
        default: break
        }

        let size: CGSize
        switch style {
        case 1:  size = CGSize(width: 11, height: 6)    // almendrados
        case 2:  size = CGSize(width: 12, height: 11)   // grandes
        case 3:  size = CGSize(width: 7,  height: 6)    // chicos
        case 6:  size = CGSize(width: 10, height: 8)    // enojados
        case 7:  size = CGSize(width: 12, height: 13)   // asombrados
        default: size = CGSize(width: 10, height: 9)    // redondos
        }

        let box = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2,
                         width: size.width, height: size.height)
        ctx.fill(Path(ellipseIn: box), with: .color(.white))

        let irisR = min(size.width, size.height) * 0.46
        let irisBox = CGRect(x: c.x - irisR, y: c.y - irisR + 0.5,
                             width: irisR * 2, height: irisR * 2)
        ctx.fill(Path(ellipseIn: irisBox), with: .color(iris))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - irisR * 0.42, y: c.y - irisR * 0.42 + 0.5,
                                        width: irisR * 0.84, height: irisR * 0.84)),
                 with: .color(ink))
        // Brillo: el detalle que separa un ojo vivo de un botón.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - irisR * 0.1, y: c.y - irisR * 0.65,
                                        width: irisR * 0.42, height: irisR * 0.42)),
                 with: .color(.white.opacity(0.9)))

        ctx.stroke(Path(ellipseIn: box), with: .color(ink.opacity(0.75)), lineWidth: 1)

        // Los enojados llevan el párpado caído hacia adentro.
        if style == 6 {
            var lid = Path()
            lid.move(to: CGPoint(x: c.x + mirror * 6, y: c.y - 5))
            lid.addLine(to: CGPoint(x: c.x - mirror * 6, y: c.y - 2))
            lid.addLine(to: CGPoint(x: c.x - mirror * 6, y: c.y - 7))
            lid.closeSubpath()
            ctx.fill(lid, with: .color(ink))
        }
    }

    // MARK: Cejas

    private static func drawBrows(_ m: Mii, ctx: inout GraphicsContext) {
        let (l, r) = eyeCenters(m)
        let color = (MiiCatalog.hairColors[safe: m.hairColor] ?? .black).opacity(0.92)
        for (c, mirror) in [(l, -1.0), (r, 1.0)] {
            let y = c.y - 9
            var p = Path()
            switch m.brows {
            case 1: // arqueadas
                p.move(to: CGPoint(x: c.x - 6, y: y + 2))
                p.addQuadCurve(to: CGPoint(x: c.x + 6, y: y + 2),
                               control: CGPoint(x: c.x, y: y - 5))
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: 2, lineCap: .round))
            case 2: // gruesas
                ctx.fill(Path(roundedRect: CGRect(x: c.x - 7, y: y - 2, width: 14, height: 4),
                              cornerRadius: 2), with: .color(color))
            case 3: // finas
                p.move(to: CGPoint(x: c.x - 6, y: y))
                p.addLine(to: CGPoint(x: c.x + 6, y: y))
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: 1.2, lineCap: .round))
            case 4: // enojadas: bajan hacia la nariz
                p.move(to: CGPoint(x: c.x - mirror * 6, y: y - 2))
                p.addLine(to: CGPoint(x: c.x + mirror * 6, y: y + 3))
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: 2.4, lineCap: .round))
            case 5: // sorprendidas: altas y curvas
                p.move(to: CGPoint(x: c.x - 6, y: y - 1))
                p.addQuadCurve(to: CGPoint(x: c.x + 6, y: y - 1),
                               control: CGPoint(x: c.x, y: y - 8))
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: 1.8, lineCap: .round))
            default: // rectas
                p.move(to: CGPoint(x: c.x - 6, y: y))
                p.addLine(to: CGPoint(x: c.x + 6, y: y - 1))
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: 2.2, lineCap: .round))
            }
        }
    }

    // MARK: Nariz

    private static func drawNose(_ m: Mii, ctx: inout GraphicsContext, skin: Color) {
        let y = 62 + (m.eyeLevel - 0.5) * 6
        let shade = Color.black.opacity(0.16)
        var p = Path()
        switch m.nose {
        case 1: // respingada
            p.move(to: CGPoint(x: 46, y: y + 3))
            p.addQuadCurve(to: CGPoint(x: 54, y: y + 2),
                           control: CGPoint(x: 50, y: y + 7))
            ctx.stroke(p, with: .color(shade), style: .init(lineWidth: 1.8, lineCap: .round))
        case 2: // ancha
            ctx.fill(Path(ellipseIn: CGRect(x: 43, y: y - 1, width: 14, height: 7)),
                     with: .color(shade))
        case 3: // larga
            p.move(to: CGPoint(x: 50, y: y - 8))
            p.addLine(to: CGPoint(x: 50, y: y + 3))
            p.addQuadCurve(to: CGPoint(x: 55, y: y + 3),
                           control: CGPoint(x: 53, y: y + 6))
            ctx.stroke(p, with: .color(shade), style: .init(lineWidth: 1.6, lineCap: .round))
        case 4: // chica
            ctx.fill(Path(ellipseIn: CGRect(x: 47.5, y: y, width: 5, height: 4)),
                     with: .color(shade))
        default: // botón
            ctx.fill(Path(ellipseIn: CGRect(x: 45.5, y: y - 1, width: 9, height: 7)),
                     with: .color(shade))
        }
    }

    // MARK: Boca

    private static func drawMouth(_ m: Mii, ctx: inout GraphicsContext) {
        let y = 74 + (m.mouthLevel - 0.5) * 10
        let ink = Color(.sRGB, red: 0.35, green: 0.16, blue: 0.14, opacity: 1)
        var p = Path()

        switch m.mouth {
        case 1: // risa abierta
            p.move(to: CGPoint(x: 41, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: 59, y: y - 2), control: CGPoint(x: 50, y: y + 10))
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))
            var tongue = Path()
            tongue.addEllipse(in: CGRect(x: 46, y: y + 2, width: 8, height: 5))
            ctx.fill(tongue, with: .color(Color(.sRGB, red: 0.80, green: 0.44, blue: 0.44, opacity: 1)))
        case 2: // neutra
            p.move(to: CGPoint(x: 44, y: y + 1))
            p.addLine(to: CGPoint(x: 56, y: y + 1))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2, lineCap: .round))
        case 3: // seria
            p.move(to: CGPoint(x: 43, y: y + 2))
            p.addQuadCurve(to: CGPoint(x: 57, y: y + 2), control: CGPoint(x: 50, y: y - 1))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2, lineCap: .round))
        case 4: // sorpresa
            ctx.fill(Path(ellipseIn: CGRect(x: 45, y: y - 3, width: 10, height: 12)),
                     with: .color(ink))
        case 5: // ladeada
            p.move(to: CGPoint(x: 43, y: y + 3))
            p.addQuadCurve(to: CGPoint(x: 57, y: y - 1), control: CGPoint(x: 50, y: y + 6))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2.2, lineCap: .round))
        case 6: // triste
            p.move(to: CGPoint(x: 43, y: y + 4))
            p.addQuadCurve(to: CGPoint(x: 57, y: y + 4), control: CGPoint(x: 50, y: y - 3))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2, lineCap: .round))
        case 7: // dientes
            p.move(to: CGPoint(x: 41, y: y - 1))
            p.addQuadCurve(to: CGPoint(x: 59, y: y - 1), control: CGPoint(x: 50, y: y + 9))
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))
            ctx.fill(Path(roundedRect: CGRect(x: 43, y: y - 1, width: 14, height: 4),
                          cornerRadius: 1), with: .color(.white))
        default: // sonrisa
            p.move(to: CGPoint(x: 43, y: y))
            p.addQuadCurve(to: CGPoint(x: 57, y: y), control: CGPoint(x: 50, y: y + 8))
            ctx.stroke(p, with: .color(ink), style: .init(lineWidth: 2.2, lineCap: .round))
        }
    }

    // MARK: Barba

    private static func drawBeard(_ m: Mii, ctx: inout GraphicsContext, color: Color) {
        guard m.beard > 0 else { return }
        let y = 74 + (m.mouthLevel - 0.5) * 10
        let r = faceRect(m.face)

        switch m.beard {
        case 1: // bigote
            var p = Path()
            p.move(to: CGPoint(x: 41, y: y - 5))
            p.addQuadCurve(to: CGPoint(x: 50, y: y - 3), control: CGPoint(x: 45, y: y - 8))
            p.addQuadCurve(to: CGPoint(x: 59, y: y - 5), control: CGPoint(x: 55, y: y - 8))
            p.addQuadCurve(to: CGPoint(x: 50, y: y - 7), control: CGPoint(x: 50, y: y - 1))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        case 2: // candado
            var p = Path()
            p.addEllipse(in: CGRect(x: 44, y: y + 4, width: 12, height: 9))
            ctx.fill(p, with: .color(color))
            ctx.fill(Path(roundedRect: CGRect(x: 42, y: y - 6, width: 16, height: 3),
                          cornerRadius: 1.5), with: .color(color))
        case 3: // completa
            var p = Path()
            p.move(to: CGPoint(x: r.minX + 3, y: y - 10))
            p.addQuadCurve(to: CGPoint(x: 50, y: r.maxY + 2),
                           control: CGPoint(x: r.minX + 5, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 3, y: y - 10),
                           control: CGPoint(x: r.maxX - 5, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: 50, y: y + 2),
                           control: CGPoint(x: 50, y: y - 6))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        case 4: // de tres días
            var p = Path()
            p.move(to: CGPoint(x: r.minX + 5, y: y - 8))
            p.addQuadCurve(to: CGPoint(x: 50, y: r.maxY),
                           control: CGPoint(x: r.minX + 7, y: r.maxY - 2))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 5, y: y - 8),
                           control: CGPoint(x: r.maxX - 7, y: r.maxY - 2))
            p.closeSubpath()
            ctx.fill(p, with: .color(color.opacity(0.28)))
        default: break
        }
    }

    // MARK: Pelo

    private static func drawHairBack(_ style: Int, ctx: inout GraphicsContext, color: Color) {
        switch style {
        case 6: // largo: cae por detrás de los hombros
            ctx.fill(Path(roundedRect: CGRect(x: 22, y: 30, width: 56, height: 66),
                          cornerRadius: 26), with: .color(color))
        case 5: // media melena
            ctx.fill(Path(roundedRect: CGRect(x: 24, y: 30, width: 52, height: 48),
                          cornerRadius: 24), with: .color(color))
        case 7: // coletas
            ctx.fill(Path(ellipseIn: CGRect(x: 14, y: 44, width: 16, height: 22)),
                     with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: 70, y: 44, width: 16, height: 22)),
                     with: .color(color))
        case 8: // moño
            ctx.fill(Path(ellipseIn: CGRect(x: 38, y: 12, width: 24, height: 20)),
                     with: .color(color))
        case 9: // afro
            ctx.fill(Path(ellipseIn: CGRect(x: 18, y: 16, width: 64, height: 58)),
                     with: .color(color))
        default: break
        }
    }

    private static func drawHairFront(_ style: Int, ctx: inout GraphicsContext,
                                      color: Color, face: CGRect) {
        guard style != 0 else { return }
        let top = face.minY
        var p = Path()

        switch style {
        case 2: // flequillo recto
            p.move(to: CGPoint(x: face.minX - 1, y: top + 16))
            p.addQuadCurve(to: CGPoint(x: face.maxX + 1, y: top + 16),
                           control: CGPoint(x: 50, y: top - 14))
            p.addLine(to: CGPoint(x: face.maxX + 1, y: top + 12))
            p.addLine(to: CGPoint(x: face.minX - 1, y: top + 12))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        case 3: // raya al costado
            p.move(to: CGPoint(x: face.minX - 1, y: top + 18))
            p.addQuadCurve(to: CGPoint(x: face.maxX + 1, y: top + 8),
                           control: CGPoint(x: 42, y: top - 12))
            p.addQuadCurve(to: CGPoint(x: face.minX - 1, y: top + 10),
                           control: CGPoint(x: 40, y: top + 2))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        case 4: // punk
            for i in 0..<5 {
                let x = 32.0 + Double(i) * 9
                var spike = Path()
                spike.move(to: CGPoint(x: x, y: top + 10))
                spike.addLine(to: CGPoint(x: x + 4.5, y: top - 12))
                spike.addLine(to: CGPoint(x: x + 9, y: top + 10))
                spike.closeSubpath()
                ctx.fill(spike, with: .color(color))
            }
            ctx.fill(Path(roundedRect: CGRect(x: face.minX - 1, y: top + 2,
                                              width: face.width + 2, height: 12),
                          cornerRadius: 6), with: .color(color))
        case 10: // rapado
            p.addEllipse(in: CGRect(x: face.minX - 1, y: top - 2,
                                    width: face.width + 2, height: 26))
            ctx.fill(p, with: .color(color.opacity(0.55)))
        case 11: // rulos
            for i in 0..<7 {
                let a = Double(i) / 6 * .pi
                let x = 50 - cos(a) * (face.width / 2)
                let y = top + 6 - sin(a) * 12
                ctx.fill(Path(ellipseIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16)),
                         with: .color(color))
            }
        default: // 1, 5, 6, 7, 8, 9: casquete
            p.addEllipse(in: CGRect(x: face.minX - 2, y: top - 6,
                                    width: face.width + 4, height: 34))
            ctx.fill(p, with: .color(color))
        }
    }

    // MARK: Lentes

    private static func drawGlasses(_ m: Mii, ctx: inout GraphicsContext) {
        guard m.glasses > 0 else { return }
        let (l, r) = eyeCenters(m)
        let color = MiiCatalog.glassColors[safe: m.glassColor] ?? .black

        func lens(_ c: CGPoint) -> Path {
            switch m.glasses {
            case 1: return Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
            case 2: return Path(roundedRect: CGRect(x: c.x - 9, y: c.y - 7, width: 18, height: 14),
                                cornerRadius: 3)
            case 3: return Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 7, width: 18, height: 13))
            case 4: return Path(roundedRect: CGRect(x: c.x - 10, y: c.y - 8, width: 20, height: 16),
                                cornerRadius: 5)
            default: return Path(roundedRect: CGRect(x: c.x - 9, y: c.y - 7, width: 18, height: 14),
                                 cornerRadius: 4)
            }
        }

        let width: Double = m.glasses == 4 ? 3 : 1.8
        for c in [l, r] {
            // Los de sol llevan cristal opaco; el resto deja ver el ojo.
            if m.glasses == 5 {
                ctx.fill(lens(c), with: .color(color.opacity(0.82)))
            }
            ctx.stroke(lens(c), with: .color(color), lineWidth: width)
        }

        var bridge = Path()
        bridge.move(to: CGPoint(x: l.x + 9, y: l.y))
        bridge.addLine(to: CGPoint(x: r.x - 9, y: r.y))
        ctx.stroke(bridge, with: .color(color), lineWidth: width)
    }
}

// MARK: - Utilidad

/// Índices fuera de rango devuelven nil en vez de reventar: un Mii guardado con
/// una versión que tenía más piezas no debería tirar la app abajo.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
