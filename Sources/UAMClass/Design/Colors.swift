import SwiftUI

// MARK: - Paleta "Wii U · UAM"
//
// Blanco de consola y el celeste institucional. La referencia es el menú de la
// Wii U: superficies BLANCAS puras sobre un fondo apenas gris, hairlines finas,
// esquinas muy redondeadas y un único color que manda — acá, el celeste de la
// UAM (#4396A6).
//
// Reglas del sistema:
//  · El blanco es la superficie, no el fondo. El fondo es gris claro para que
//    los paneles blancos floten sobre él, como los mosaicos del menú.
//  · El color se usa con moderación y siempre para señalar acción o selección.
//    Todo lo demás es blanco, gris y tinta.
//  · Los estados sí son de colores francos. Una consola no comunica "vencido"
//    con un sepia apagado: lo dice en rojo.
//
// Se conservan TODOS los nombres de token para que las vistas no cambien: se
// reemplazan los valores y la app entera se retiñe sola.

/// El celeste de la UAM, muestreado del logotipo real (`uam-logo.png`): el
/// cian dominante de las letras es `#0098B8`.
///
/// El acento de la interfaz es una versión apenas más oscura. No es capricho:
/// `#0098B8` sobre blanco da 3.3:1 de contraste, y los antetítulos de 9.5 pt
/// necesitan 4.5:1 para ser legibles. El cian del logo se conserva intacto en
/// `bay` y en los degradés de los mosaicos, donde es relleno y no texto.
let uamCyan: UInt32 = 0x0098B8

enum Palette {

    // MARK: Marca

    static let accent       = dyn(light: 0x0A85A3, dark: 0x35BEDC)
    static let accentHover  = dyn(light: 0x086B85, dark: 0x6BD6EE)
    static let accentSoft   = dyn(light: 0xDFF3F8, dark: 0x0F2E38)
    static let accentGlow   = dyn(light: 0x18B8D0, dark: 0x7FE0F2)

    /// Secundarios: un celeste más hondo y uno más claro. Mantienen los nombres
    /// del sistema anterior para no tocar las vistas.
    /// El cian del logotipo, sin corregir. Para rellenos y láminas.
    static let bay          = dyn(light: 0x0098B8, dark: 0x5FCBE2)
    static let baySoft      = dyn(light: 0xD9F0F6, dark: 0x12333C)
    static let gold         = dyn(light: 0x18B8D0, dark: 0x8FE2F2)

    // MARK: Superficies

    /// Fondo: gris muy claro y apenas frío, para que el blanco de los paneles
    /// se lea como blanco y no se funda con la ventana.
    // Neutro, no celeste. Un fondo teñido le competía a los mosaicos y le ponía
    // un velo de color a toda la app.
    static let canvas          = dyn(light: 0xF4F6F7, dark: 0x101416)
    static let background      = dyn(light: 0xF4F6F7, dark: 0x101416)
    /// Los paneles: blanco puro. Es el corazón de la estética.
    static let surface         = dyn(light: 0xFFFFFF, dark: 0x1B2429)
    static let surfaceHover    = dyn(light: 0xF6FAFB, dark: 0x223035)
    static let surfaceElevated = dyn(light: 0xFFFFFF, dark: 0x222D33)

    static let scrim           = dynA(light: 0x0E1F24, lightAlpha: 0.28,
                                      dark:  0x000000, darkAlpha:  0.58)

    // MARK: Reglas

    static let border          = dynA(light: 0x2E5560, lightAlpha: 0.14,
                                      dark:  0xAFD8E2, darkAlpha:  0.14)
    static let borderStrong    = dynA(light: 0x2E5560, lightAlpha: 0.26,
                                      dark:  0xAFD8E2, darkAlpha:  0.26)
    static let divider         = dynA(light: 0x2E5560, lightAlpha: 0.09,
                                      dark:  0xAFD8E2, darkAlpha:  0.08)

    // MARK: Texto

    static let textPrimary     = dyn(light: 0x18292F, dark: 0xEAF4F7)
    static let textSecondary   = dyn(light: 0x445A62, dark: 0xB2C7CE)
    static let textTertiary    = dyn(light: 0x6D848C, dark: 0x89A0A8)
    static let textQuaternary  = dyn(light: 0x9BAFB6, dark: 0x60767E)
    static let textOnAccent    = dyn(light: 0xFFFFFF, dark: 0x0C1417)

    // MARK: Estados
    //
    // Francos, no apagados. Una consola dice las cosas de frente.

    static let success         = dyn(light: 0x3AA06A, dark: 0x6ED39C)
    static let warning         = dyn(light: 0xD9903A, dark: 0xF2BE70)
    static let danger          = dyn(light: 0xD4544C, dark: 0xF08880)

    // MARK: Filos
    //
    // Acá SÍ hay brillo: los mosaicos de la Wii U son plásticos, con una luz
    // sutil arriba y una sombra fina abajo. Es lo que los hace ver pulsables.

    static var rim: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.95), Color.white.opacity(0.25),
                     Color.black.opacity(0.045)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var rimOnDark: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.18), Color.clear, Color.black.opacity(0.22)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Reflejo especular suave sobre la mitad superior: el plástico brillante.
    static var specular: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.55), location: 0.0),
                .init(color: .white.opacity(0.10), location: 0.45),
                .init(color: .clear,               location: 0.55),
                .init(color: .clear,               location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Ambiente

    /// Degradé suave de celestes para los fondos: el menú de la consola nunca
    /// es un plano muerto, siempre tiene una respiración de color.
    /// Compat: el ambiente ya no es una malla de color. Se devuelve el lienzo
    /// plano para las vistas viejas que todavía lo piden.
    static func ambientMesh(tint: Color, dark: Bool) -> [Color] {
        Array(repeating: Color(hex: dark ? 0x101416 : 0xF4F6F7), count: 9)
    }

    // MARK: Helpers

    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        dynA(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    private static func dynA(light: UInt32, lightAlpha: Double,
                             dark: UInt32, darkAlpha: Double) -> Color {
        .dynamicRGB(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha)
    }
}

// MARK: - Utilidades de color

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func mixed(with other: Color, amount: Double) -> Color {
        let a = self.srgbComponents
        let b = other.srgbComponents
        let t = max(0, min(1, amount))
        return Color(.sRGB,
                     red:   a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue:  a.b + (b.b - a.b) * t,
                     opacity: a.a + (b.a - a.a) * t)
    }

    var readable: Color { self }

    /// Antes era un degradé de marca a 135°. En el códice, la "tinta" apenas
    /// varía de un extremo al otro: un lavado de aguada, no un gradiente vivo.
    var brandGradient: LinearGradient {
        LinearGradient(
            colors: [mixed(with: .white, amount: 0.10), self,
                     mixed(with: .black, amount: 0.14)],
            startPoint: .top, endPoint: .bottom
        )
    }

    func halo(_ opacity: Double) -> Color { self.opacity(opacity) }
}
