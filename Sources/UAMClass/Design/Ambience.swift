import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Fondo de papel
//
// Reemplaza al MeshGradient de colores del sistema anterior. Es una hoja: color
// plano cálido, grano fino en multiply, y un viñeteado que oscurece los bordes
// como la sombra de un libro abierto. Sin color, sin movimiento llamativo.

/// El fondo del sistema.
///
/// La versión anterior eran cuatro masas de color derivando, y se veía como el
/// fondo de cualquier landing: un degradé celeste sin estructura. El menú de una
/// consola no es eso — es una superficie CLARA Y NEUTRA con una trama fina y
/// geométrica encima, casi imperceptible, que le da textura sin pedir atención.
///
/// Tres decisiones:
///
///  · **Sin color de fondo.** El lienzo es gris casi blanco. Todo el color de la
///    app vive en los mosaicos, que es donde tiene que estar; un fondo teñido
///    les competía y le daba a todo un velo celeste.
///  · **Trama, no manchas.** Hairlines diagonales y una retícula de puntos, en
///    tinta al 2-4 %. Estructura en vez de humo.
///  · **Deriva mínima.** La trama se corre despacio en diagonal. Lo justo para
///    que la superficie esté viva; nada que se note si la mirás de frente.
struct AmbientBackdrop: View {
    var tint: Color = Palette.accent
    var intensity: Double = 1.0

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.canvas

            // Luz cenital: el menú siempre parece iluminado desde arriba.
            LinearGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.05 : 0.75),
                         Color.clear],
                startPoint: .top, endPoint: .center)

            if reduceMotion {
                Canvas { ctx, size in
                    Self.weave(ctx: &ctx, size: size, phase: 0,
                               dark: scheme == .dark, intensity: intensity)
                }
            } else {
                // 12 fps alcanza y sobra: la trama se mueve 8 puntos por minuto.
                // A 24 costaba el doble para un movimiento que nadie ve.
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    Canvas { ctx, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Self.weave(ctx: &ctx, size: size, phase: t,
                                   dark: scheme == .dark, intensity: intensity)
                    }
                }
            }

            // Viñeta discreta: recoge los bordes para que el contenido flote.
            RadialGradient(
                colors: [.clear,
                         (scheme == .dark ? Color.black : Color(hex: 0x243B42))
                            .opacity((scheme == .dark ? 0.30 : 0.05) * intensity)],
                center: .center, startRadius: 260, endRadius: 900)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// La trama: diagonales finas + retícula de puntos.
    private static func weave(ctx: inout GraphicsContext, size: CGSize,
                              phase: Double, dark: Bool, intensity: Double) {
        let w = size.width, h = size.height
        let ink = dark ? Color.white : Color(hex: 0x11333B)

        // Deriva de 8 pt por minuto sobre el paso de la trama.
        let stripe: Double = 74
        let drift = (phase * 0.13).truncatingRemainder(dividingBy: stripe)

        var lines = Path()
        var x = -h - stripe + drift
        while x < w + stripe {
            lines.move(to: CGPoint(x: x, y: h))
            lines.addLine(to: CGPoint(x: x + h, y: 0))
            x += stripe
        }
        ctx.stroke(lines, with: .color(ink.opacity((dark ? 0.035 : 0.028) * intensity)),
                   lineWidth: 1)

        // Retícula de puntos, con su propia deriva más lenta y en otra dirección
        // para que las dos tramas nunca se sincronicen en un patrón obvio.
        let step: Double = 46
        let dotDrift = (phase * 0.07).truncatingRemainder(dividingBy: step)
        var dots = Path()
        var gy = -step + dotDrift
        while gy < h + step {
            var gx = -step + dotDrift * 0.5
            while gx < w + step {
                dots.addEllipse(in: CGRect(x: gx - 1, y: gy - 1, width: 2, height: 2))
                gx += step
            }
            gy += step
        }
        ctx.fill(dots, with: .color(ink.opacity((dark ? 0.07 : 0.05) * intensity)))
    }
}

// MARK: - Grano de papel

/// Ruido monocromo tileado, en `multiply`, para dar textura de fibra a la hoja.
/// Se genera una sola vez.
struct PaperGrain: View {
    var body: some View {
        Image(platformImage: PaperGrain.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }

    private static let tile: PlatformImage = makeTile(side: 150)

    private static func makeTile(side: Int) -> PlatformImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var seed: UInt64 = 0xC0FFEE1234567
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            // Ruido apretado alrededor del gris medio: fibra sutil, no estática.
            let n = UInt8(truncatingIfNeeded: seed >> 24)
            let v = UInt8(120 + Int(n) % 40)
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            pixels[i + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: side, height: side,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: bytesPerRow,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent)
        else {
            #if canImport(AppKit)
            return NSImage(size: NSSize(width: side, height: side))
            #elseif canImport(UIKit)
            return UIImage()
            #endif
        }
        #if canImport(AppKit)
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
        #elseif canImport(UIKit)
        return UIImage(cgImage: cg)
        #endif
    }
}

// Alias para el código que aún nombra al grano viejo.
typealias GrainOverlay = PaperGrain

extension View {
    func ambientBackground(tint: Color = Palette.accent, intensity: Double = 1.0) -> some View {
        self.background(AmbientBackdrop(tint: tint, intensity: intensity))
    }
}
