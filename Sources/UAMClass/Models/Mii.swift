import SwiftUI

// MARK: - Mii
//
// Un avatar armado por piezas, al estilo de los editores de consola. Se guarda
// como una lista de ÍNDICES, no como una imagen: ocupa nada, se puede volver a
// editar siempre, y se redibuja nítido a cualquier tamaño — desde los 22 puntos
// de un mensaje de foro hasta los 160 del editor.
//
// Todas las formas son originales, dibujadas con curvas en un lienzo de 100×100
// (ver `MiiRenderer`). No hay recursos de nadie más adentro.

struct Mii: Codable, Equatable, Hashable {
    var face: Int = 0
    var skin: Int = 2
    var hair: Int = 1
    var hairColor: Int = 0
    var eyes: Int = 0
    var eyeColor: Int = 0
    var brows: Int = 0
    var nose: Int = 0
    var mouth: Int = 0
    var beard: Int = 0
    var glasses: Int = 0
    var glassColor: Int = 0
    var background: Int = 0

    /// Ajustes finos, 0…1 con 0.5 al centro. Son los que hacen que dos Miis con
    /// las mismas piezas no se vean iguales.
    var eyeSpacing: Double = 0.5
    var eyeLevel: Double = 0.5
    var mouthLevel: Double = 0.5

    /// Mii ESTABLE para una persona: el mismo id siempre da la misma cara.
    ///
    /// Es lo que permite que todo el mundo tenga Mii sin que nadie lo haya
    /// creado — como el desfile de Miis de la consola. Y al ser estable, la cara
    /// se vuelve reconocible: dejás de leer nombres y empezás a reconocer gente.
    static func deterministic(seed: String) -> Mii {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(StableHash.of(seed))))
        return random(using: &rng)
    }

    static func random() -> Mii {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    static func random<G: RandomNumberGenerator>(using rng: inout G) -> Mii {
        Mii(face: .random(in: 0..<MiiCatalog.faceCount, using: &rng),
            skin: .random(in: 0..<MiiCatalog.skins.count, using: &rng),
            hair: .random(in: 0..<MiiCatalog.hairCount, using: &rng),
            hairColor: .random(in: 0..<MiiCatalog.hairColors.count, using: &rng),
            eyes: .random(in: 0..<MiiCatalog.eyeCount, using: &rng),
            eyeColor: .random(in: 0..<MiiCatalog.eyeColors.count, using: &rng),
            brows: .random(in: 0..<MiiCatalog.browCount, using: &rng),
            nose: .random(in: 0..<MiiCatalog.noseCount, using: &rng),
            mouth: .random(in: 0..<MiiCatalog.mouthCount, using: &rng),
            // La barba y los lentes casi siempre en "ninguno": si salieran
            // parejos, tres de cada cuatro Miis al azar tendrían barba.
            beard: Bool.random(using: &rng) && Bool.random(using: &rng) ? .random(in: 1..<MiiCatalog.beardCount, using: &rng) : 0,
            glasses: Bool.random(using: &rng) && Bool.random(using: &rng) ? .random(in: 1..<MiiCatalog.glassesCount, using: &rng) : 0,
            glassColor: .random(in: 0..<MiiCatalog.glassColors.count, using: &rng),
            background: .random(in: 0..<MiiCatalog.backgrounds.count, using: &rng),
            eyeSpacing: .random(in: 0.25...0.75, using: &rng),
            eyeLevel: .random(in: 0.3...0.7, using: &rng),
            mouthLevel: .random(in: 0.3...0.7, using: &rng))
    }
}

// MARK: - Catálogo

enum MiiCatalog {
    static let faceCount    = 6
    static let hairCount    = 12
    static let eyeCount     = 8
    static let browCount    = 6
    static let noseCount    = 5
    static let mouthCount   = 8
    static let beardCount   = 5
    static let glassesCount = 6

    static let skins: [Color] = [
        rgb(0xF6DCC4), rgb(0xEFC9A6), rgb(0xE0AC80), rgb(0xC98E63),
        rgb(0xA9714A), rgb(0x845234), rgb(0x5E3A24), rgb(0xFAE7D6)
    ]

    static let hairColors: [Color] = [
        rgb(0x2B2118), rgb(0x4A3427), rgb(0x6E4B31), rgb(0x9A6B3F),
        rgb(0xC9A063), rgb(0xE3CDA4), rgb(0x8A8378), rgb(0x6B2E2E)
    ]

    static let eyeColors: [Color] = [
        rgb(0x3B2A1C), rgb(0x5C4327), rgb(0x2F5D4E), rgb(0x2E4E6E),
        rgb(0x6B6257), rgb(0x1E1B18)
    ]

    static let glassColors: [Color] = [
        rgb(0x2B2118), rgb(0x8A6A3E), rgb(0x6E6A62), rgb(0xB8A272), rgb(0x5E3A24)
    ]

    /// Fondos sobrios, para que el Mii siga viéndose como parte del manuscrito
    /// y no como una calcomanía pegada encima.
    static let backgrounds: [Color] = [
        rgb(0xE9E5DC), rgb(0xD9D3C6), rgb(0xC8CFC9), rgb(0xD8CEC0),
        rgb(0xCBC7D2), rgb(0xE2D6C3), rgb(0xBFC6CC), rgb(0xDCD0D0)
    ]

    static let faceNames   = ["Redonda", "Ovalada", "Cuadrada", "Corazón", "Alargada", "Angulosa"]
    static let hairNames   = ["Sin pelo", "Corto", "Flequillo", "Raya al lado", "Punk", "Media melena",
                              "Largo", "Coletas", "Moño", "Afro", "Rapado", "Rulos"]
    static let eyeNames    = ["Redondos", "Almendrados", "Grandes", "Chicos",
                              "Contentos", "Dormidos", "Enojados", "Asombrados"]
    static let browNames   = ["Rectas", "Arqueadas", "Gruesas", "Finas", "Enojadas", "Sorprendidas"]
    static let noseNames   = ["Botón", "Respingada", "Ancha", "Larga", "Chica"]
    static let mouthNames  = ["Sonrisa", "Risa", "Neutra", "Seria", "Sorpresa", "Ladeada", "Triste", "Dientes"]
    static let beardNames  = ["Sin barba", "Bigote", "Candado", "Completa", "De tres días"]
    static let glassNames  = ["Sin lentes", "Redondos", "Cuadrados", "Aviador", "Gruesos", "De sol"]

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red:   Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue:  Double(hex & 0xFF) / 255,
              opacity: 1)
    }
}


// MARK: - Generador con semilla

/// xorshift64*. Determinístico y sin dependencias: la misma semilla da siempre
/// la misma secuencia, en esta y en cualquier otra Mac.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
