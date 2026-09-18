import SwiftUI

/// Tono por curso — en el códice, una rampa de GRAFITOS, no de colores.
///
/// Cada materia recibe una tinta distinta dentro de una escala de grises
/// cálidos (de la tinta casi negra al grafito claro). Se distinguen por valor,
/// no por matiz, fiel al blanco/negro/grafito.
enum CourseAccent {

    private struct Tone { let deep: UInt32; let lift: UInt32 }

    // Ocho grafitos, del más oscuro al más claro. Cálidos apenas (matiz sepia
    // mínimo) para que convivan con el papel y no se vean azulados.
    private static let palette: [Tone] = [
        Tone(deep: 0x2A2620, lift: 0x8E887B),
        Tone(deep: 0x3A352C, lift: 0x9A9384),
        Tone(deep: 0x4A443A, lift: 0xA6A08F),
        Tone(deep: 0x585144, lift: 0xB0A997),
        Tone(deep: 0x38332B, lift: 0x928B7D),
        Tone(deep: 0x484236, lift: 0xA29B89),
        Tone(deep: 0x554E41, lift: 0xACA593),
        Tone(deep: 0x322E27, lift: 0x8A8376)
    ]

    private static func index(for key: String) -> Int {
        var h: UInt64 = 5381
        for b in key.utf8 { h = (h &* 33) &+ UInt64(b) }
        return Int(h % UInt64(palette.count))
    }

    static func color(for course: MoodleCourse) -> Color {
        let tone = palette[index(for: course.shortname)]
        return Color.dynamicRGB(light: tone.deep, dark: tone.lift)
    }

    static func softColor(for course: MoodleCourse) -> Color {
        color(for: course).opacity(0.12)
    }

    static func gradient(for course: MoodleCourse) -> LinearGradient {
        let base = color(for: course)
        return LinearGradient(
            colors: [base.mixed(with: .white, amount: 0.06), base,
                     base.mixed(with: .black, amount: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
