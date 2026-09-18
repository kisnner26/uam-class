import SwiftUI

/// Presets de animación. Regla: nada por debajo de 120ms (se lee como glitch)
/// ni por encima de 500ms (se lee como lag). Los rebotes solo en cosas que
/// el usuario acaba de tocar.
enum Motion {
    /// Movimientos principales: aparecer, cambiar de pantalla, expandir.
    static let spring = Animation.smooth(duration: 0.38, extraBounce: 0.08)

    /// Feedback inmediato: hover, press, focus.
    static let quick = Animation.snappy(duration: 0.18, extraBounce: 0.0)

    /// Cross-fade de contenido.
    static let fade = Animation.easeInOut(duration: 0.22)

    /// Push/pop de vistas grandes.
    static let route = Animation.smooth(duration: 0.45)

    /// Algo que aparece de la nada y quiere que lo mires (toast, palette).
    static let pop = Animation.bouncy(duration: 0.34, extraBounce: 0.18)

    /// Deriva del fondo ambiental. Lentísima a propósito: se debe notar solo
    /// si te quedás mirando.
    static let ambient = Animation.easeInOut(duration: 14).repeatForever(autoreverses: true)

    /// Escalonado para listas y grids que entran.
    static func stagger(_ index: Int, step: Double = 0.035, cap: Int = 12) -> Animation {
        spring.delay(Double(min(index, cap)) * step)
    }
}

// MARK: - Filas al estilo consola

extension View {
    /// Hover con sonido. Reemplaza al `.consoleHover($hovered)` suelto: hace
    /// lo mismo y además dispara el chirrido, que es lo que hace que la
    /// interfaz se sienta viva en vez de silenciosa.
    func consoleHover(_ hovered: Binding<Bool>) -> some View {
        self.onHover { on in
            hovered.wrappedValue = on
            if on { SoundKit.shared.play(.hover) }
        }
    }
}

/// Realce de fila: cápsula del color de acento en vez de un gris plano.
struct RowHighlight: View {
    let hovered: Bool
    var tint: Color
    var radius: CGFloat = Radius.md

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(hovered ? 0.10 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(hovered ? 0.28 : 0), lineWidth: 1)
            )
            .padding(.horizontal, 4)
            .allowsHitTesting(false)
    }
}
