import SwiftUI

// MARK: - Escala de calificaciones de la UAM
//
// El año se divide en dos SEMESTRES (ver `AcademicPeriod`), y cada semestre en
// TRES CORTES de 100 puntos cada uno. O sea 300 puntos por materia, por semestre.
//
//   · 210 puntos o más (70 promediado) → aprobada
//   · 180 a 209        (60 a 69)       → derecho a examen de convocatoria
//   · menos de 180     (bajo 60)       → reprobada, sin convocatoria
//
// Moodle no sabe nada de esto: entrega puntos crudos sobre el máximo que haya
// configurado el docente, que rara vez es 300. Por eso todo se calcula sobre el
// PORCENTAJE y recién al final se lleva a la escala de 300 — así el veredicto
// sale bien aunque una materia tenga el libro de calificaciones sobre 100, sobre
// 50 o sobre 1000.

enum UAMGrading {
    static let cortes = 3
    static let pointsPerCorte: Double = 100
    static let totalPoints: Double = 300

    /// 70 promediado.
    static let passingPercent: Double = 70
    /// 60 promediado: no aprueba, pero tiene derecho a convocatoria.
    static let convocatoriaPercent: Double = 60

    static var passingPoints: Double { totalPoints * passingPercent / 100 }        // 210
    static var convocatoriaPoints: Double { totalPoints * convocatoriaPercent / 100 } // 180

    enum Standing: Hashable {
        case aprobada
        case convocatoria
        case reprobada

        var label: String {
            switch self {
            case .aprobada:     return "Aprobada"
            case .convocatoria: return "Convocatoria"
            case .reprobada:    return "Reprobada"
            }
        }

        /// Qué significa, en una línea. La app no debería obligarte a recordar
        /// los umbrales de memoria.
        var detail: String {
            switch self {
            case .aprobada:     return "70 o más promediado"
            case .convocatoria: return "entre 60 y 69 — tenés derecho a examen de convocatoria"
            case .reprobada:    return "menos de 60 — sin derecho a convocatoria"
            }
        }

        var tone: Color {
            switch self {
            case .aprobada:     return Palette.success
            case .convocatoria: return Palette.warning
            case .reprobada:    return Palette.danger
            }
        }

        var symbol: String {
            switch self {
            case .aprobada:     return "checkmark.seal.fill"
            case .convocatoria: return "arrow.clockwise.circle.fill"
            case .reprobada:    return "xmark.seal.fill"
            }
        }
    }

    static func standing(percent: Double) -> Standing {
        if percent >= passingPercent { return .aprobada }
        if percent >= convocatoriaPercent { return .convocatoria }
        return .reprobada
    }

    /// Puntos sobre 300 a partir de un porcentaje.
    static func points(fromPercent p: Double) -> Double {
        (p / 100) * totalPoints
    }
}

/// Cómo va una materia en la escala de la UAM.
///
/// Es una foto de lo que hay calificado HASTA AHORA, no una predicción: si solo
/// se llevan dos cortes, el porcentaje es sobre lo entregado, y decirlo importa
/// — "vas reprobada" con un corte pendiente sería una mentira estresante.
struct CourseStanding {
    let percent: Double
    let earnedPoints: Double
    let standing: UAMGrading.Standing
    /// Cuántos puntos de los 300 ya están en juego (es decir, calificados).
    let gradedPoints: Double

    var isPartial: Bool { gradedPoints < UAMGrading.totalPoints - 0.5 }

    /// Cuántos puntos faltan para los 210. `nil` si ya los tiene.
    var pointsToPass: Double? {
        let missing = UAMGrading.passingPoints - earnedPoints
        return missing > 0.5 ? missing : nil
    }

    /// Calcula desde los ítems del libro de calificaciones de una materia.
    ///
    /// Se prefiere el ítem "total del curso" que Moodle genera solo
    /// (`itemtype == "course"`), porque ya respeta las ponderaciones que puso el
    /// docente. Si no está, se promedian los ítems calificados a mano.
    init?(items: [MoodleGradeItem]) {
        let total = items.first { $0.itemtype == "course" }

        let pct: Double
        let graded: Double

        if let t = total, let raw = t.graderaw, let max = t.grademax, max > 0 {
            pct = raw / max * 100
            graded = UAMGrading.totalPoints
        } else {
            let scored = items.filter { $0.itemtype != "course" && $0.itemtype != "category" }
                              .compactMap { item -> (Double, Double)? in
                                  guard let raw = item.graderaw,
                                        let max = item.grademax, max > 0 else { return nil }
                                  return (raw, max)
                              }
            guard !scored.isEmpty else { return nil }
            let earned = scored.reduce(0) { $0 + $1.0 }
            let possible = scored.reduce(0) { $0 + $1.1 }
            guard possible > 0 else { return nil }
            pct = earned / possible * 100
            // Sin el total del curso no se sabe qué parte del semestre cubre
            // esto, así que se marca como parcial.
            graded = 0
        }

        self.percent = pct
        self.earnedPoints = UAMGrading.points(fromPercent: pct)
        self.standing = UAMGrading.standing(percent: pct)
        self.gradedPoints = graded
    }
}
