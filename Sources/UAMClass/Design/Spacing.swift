import Foundation
import SwiftUI

/// Escala de spacing basada en 4pt.
enum Space {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48

    /// Ancho máximo de una columna de contenido. Más allá de esto la lectura
    /// se rompe y la ventana se ve vacía en el centro.
    static let readable: CGFloat = 1160
}

/// Radios concéntricos. La regla: radio interior = radio exterior − padding.
/// Romperla es la razón número uno por la que las cards se ven "hechas a ojo".
enum Radius {
    // Esquinas cerradas: el códice es de ángulos rectos suavizados, no de
    // burbujas. Menos radio = más papel, menos app.
    // Consola, no documento: todo mucho más redondo. Es el segundo gesto que
    // más rápido cambia la lectura de la interfaz, después de la tipografía.
    static let xs: CGFloat = 5
    static let sm: CGFloat = 9
    static let md: CGFloat = 13
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 30

    /// Radio interior correcto para un hijo con `inset` de padding.
    static func inner(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, outer - inset)
    }
}

/// Sombras en dos partes: una de contacto (corta, opaca) y una ambiental
/// (larga, difusa). Una sola sombra siempre se ve plana o sucia.
enum Elevation {
    case flat, low, mid, high, floating

    var contact: (radius: CGFloat, y: CGFloat, opacity: Double) {
        switch self {
        case .flat:     return (0, 0, 0)
        case .low:      return (1.5, 1, 0.05)
        case .mid:      return (3, 2, 0.07)
        case .high:     return (5, 3, 0.09)
        case .floating: return (7, 4, 0.11)
        }
    }

    // Sombras de papel: suaves y bajas. Una hoja apoyada sobre otra no
    // proyecta la sombra profunda que sí proyectaba el vidrio flotante.
    var ambient: (radius: CGFloat, y: CGFloat, opacity: Double) {
        switch self {
        case .flat:     return (0, 0, 0)
        case .low:      return (6, 2, 0.04)
        case .mid:      return (14, 6, 0.06)
        case .high:     return (26, 11, 0.09)
        case .floating: return (44, 20, 0.16)
        }
    }
}

extension View {
    /// Sombra de dos capas. Ver `Elevation`.
    func elevation(_ level: Elevation, tint: Color = .black) -> some View {
        let c = level.contact
        let a = level.ambient
        return self
            .shadow(color: tint.opacity(c.opacity), radius: c.radius, x: 0, y: c.y)
            .shadow(color: tint.opacity(a.opacity), radius: a.radius, x: 0, y: a.y)
    }
}

/// Compatibilidad con el código previo.
enum Shadow {
    static func low(_ view: some View)  -> some View { view.elevation(.low) }
    static func mid(_ view: some View)  -> some View { view.elevation(.mid) }
    static func high(_ view: some View) -> some View { view.elevation(.high) }
}
