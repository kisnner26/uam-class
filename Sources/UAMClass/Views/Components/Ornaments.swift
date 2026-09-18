import SwiftUI

// MARK: - Ornamentos del códice
//
// Todo en tinta (currentColor). Trazos finos, grabados. Son las piezas que
// convierten una UI en un manuscrito: filigrana separadora, arco ojival que
// recorta las "láminas" (portadas de curso), marca de capítulo, capitular.

// MARK: Filigrana

/// Separador de filigrana con nudo central. Va entre bloques, como el remate
/// que corta los capítulos de un libro antiguo.
struct Filigrana: View {
    var width: CGFloat = 260
    var color: Color = Palette.textTertiary

    var body: some View {
        FiligranaShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: 22)
            .overlay(
                // Rombo central relleno: el "nudo" del ornamento.
                Diamond()
                    .fill(color)
                    .frame(width: 5, height: 5)
            )
    }
}

private struct FiligranaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let cx = rect.midX
        // Líneas rectas a los costados.
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addLine(to: CGPoint(x: cx - 46, y: midY))
        p.move(to: CGPoint(x: cx + 46, y: midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: midY))
        // Volutas simétricas hacia el centro.
        p.move(to: CGPoint(x: cx - 46, y: midY))
        p.addCurve(to: CGPoint(x: cx - 10, y: midY),
                   control1: CGPoint(x: cx - 30, y: midY - 9),
                   control2: CGPoint(x: cx - 24, y: midY + 9))
        p.move(to: CGPoint(x: cx + 46, y: midY))
        p.addCurve(to: CGPoint(x: cx + 10, y: midY),
                   control1: CGPoint(x: cx + 30, y: midY - 9),
                   control2: CGPoint(x: cx + 24, y: midY + 9))
        // Anillo alrededor del nudo.
        p.addEllipse(in: CGRect(x: cx - 8, y: midY - 8, width: 16, height: 16))
        return p
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: Arco ojival

/// Arco gótico apuntado. Recorta portadas de curso y heros, como los ventanales
/// de un claustro. `pointiness` sube la altura del arco.
struct GothicArch: Shape {
    var shoulder: CGFloat = 0.42   // dónde empieza a curvar (fracción de alto)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let s = h * shoulder
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: s))
        // Dos arcos que se encuentran en la punta.
        p.addQuadCurve(to: CGPoint(x: w / 2, y: 0),
                       control: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: s),
                       control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: Esquineras

/// Cuatro esquineras de álbum antiguo alrededor de un contenido.
struct AlbumCorners: View {
    var color: Color = Palette.textTertiary
    var inset: CGFloat = 6
    var length: CGFloat = 16

    var body: some View {
        GeometryReader { _ in
            ZStack {
                corner.position(x: inset + length/2, y: inset + length/2)
                corner.rotationEffect(.degrees(90))
                    .position(x: nil ?? 0, y: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private var corner: some View {
        CornerShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .frame(width: length, height: length)
    }
}

/// Marco con las cuatro esquineras. Más simple de usar como overlay.
struct CornerFrame: View {
    var color: Color = Palette.textTertiary
    var length: CGFloat = 15

    var body: some View {
        ZStack {
            cornerMark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cornerMark.rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            cornerMark.rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            cornerMark.rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomRight)
        }
        .allowsHitTesting(false)
    }

    private var cornerMark: some View {
        CornerShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .frame(width: length, height: length)
    }
}

private struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Pequeña voluta interior.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.minY))
        return p
    }
}

private extension Alignment {
    static let bottomRight = Alignment(horizontal: .trailing, vertical: .bottom)
}

// MARK: Marca de capítulo (patrón "runa")
//
// El encabezado de cada sección: un glifo, una línea, la etiqueta en versalitas
// y su "sentido" en cursiva. Es el patrón que abre cada capítulo del códice.

struct ChapterMark: View {
    let glyph: String        // símbolo (SF Symbol) del capítulo
    let label: String        // versalita: "MATERIAS"
    var meaning: String? = nil   // cursiva: "el saber reunido"
    var trailing: AnyView? = nil

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: glyph)
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Palette.textPrimary)

                    Rectangle()
                        .fill(Palette.borderStrong)
                        .frame(width: 34, height: 1)

                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(3.4)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let meaning {
                    Text(meaning)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

// MARK: Capitular (drop cap)

/// Letra capitular: la inicial grande, encuadrada, que abre un texto. Un guiño
/// al manuscrito iluminado sin recargar.
struct DropCap: View {
    let letter: Character
    var size: CGFloat = 46

    var body: some View {
        Text(String(letter))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .frame(width: size * 1.02, height: size * 1.02)
            .overlay(
                Rectangle().strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
    }
}

// MARK: - Utilidades de página

extension View {
    /// Encuadra la vista entre dos filigranas, como una lámina del libro.
    func illuminated(width: CGFloat = 220) -> some View {
        VStack(spacing: Space.md) {
            Filigrana(width: width)
            self
            Filigrana(width: width)
        }
    }
}
