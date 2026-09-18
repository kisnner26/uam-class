import SwiftUI

// MARK: - Tipografía "Códice"
//
// Serif para todo lo que se lee y se contempla — títulos, enunciados, cuerpo —
// usando New York (el serif del sistema, `design: .serif`). Sans solo para el
// aparato de la interfaz: micro-etiquetas en versalitas y datos monoespaciados.
//
// La firma del manuscrito es el TRACKING AMPLIO en los titulares (letras
// separadas, como grabadas) y la CURSIVA para subtítulos y definiciones.

enum Type {
    // Redondeada, no serif. Es el gesto tipográfico que más rápido dice
    // "consola": la Wii U no tenía una sola letra con remates. SF Pro Rounded
    // viene con el sistema, así que no hay que embarcar ninguna fuente.
    static let hero      = Font.system(size: 42, weight: .bold,     design: .rounded)
    static let display   = Font.system(size: 30, weight: .bold,     design: .rounded)
    static let title     = Font.system(size: 21, weight: .semibold, design: .rounded)
    static let heading   = Font.system(size: 16.5, weight: .semibold, design: .rounded)
    static let subtitle  = Font.system(size: 15, weight: .regular,  design: .rounded)
    static let body      = Font.system(size: 13.5, weight: .regular, design: .rounded)
    static let bodyBold  = Font.system(size: 13.5, weight: .semibold, design: .rounded)

    // Aparato de UI.
    static let caption   = Font.system(size: 12, weight: .medium,   design: .rounded)
    static let captionB  = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let captionU  = Font.system(size: 10, weight: .bold,     design: .rounded)
    static let micro     = Font.system(size: 10, weight: .medium,   design: .rounded)
    static let mono      = Font.system(size: 12, weight: .medium,   design: .monospaced)

    /// Cifras grandes: redondeadas y con peso, como los contadores de un menú
    /// de consola.
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Text {
    /// Versalita separada: la etiqueta de capítulo. El recurso que más "eleva"
    /// el manuscrito. Tracking generoso, como una inscripción.
    func labelCaps(tracking: CGFloat = 3.0) -> some View {
        self
            .font(Type.captionU)
            .textCase(.uppercase)
            .tracking(tracking)
            .foregroundStyle(Palette.textTertiary)
    }

    /// Titular grande. En el códice el tracking es POSITIVO (letras abiertas),
    /// al revés que en una UI moderna.
    func displayStyle(_ size: CGFloat = 32, weight: Font.Weight = .regular) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .rounded))
            .tracking(size >= 28 ? 0.5 : 0.2)
    }
}

extension View {
    func metricDigits() -> some View {
        self.monospacedDigit().contentTransition(.numericText())
    }
}
