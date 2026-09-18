import Foundation

// MARK: - Presupuesto de faltas
//
// La UAM permite faltar el 20 % del semestre. Kisnner lo dio como dos casos:
// una materia de dos sesiones semanales admite 6 faltas, y una de una sesión
// admite el 20 % de sus sesiones.
//
// Los dos casos son la MISMA regla, y de ahí sale el único número que había que
// deducir: si 6 faltas son el 20 %, el semestre tiene 30 sesiones; y 30 sesiones
// a dos por semana son **15 semanas**. Con eso, una materia de una sesión tiene
// 15 sesiones y admite 3 faltas. No hace falta promediar nada ni tratar los
// casos por separado: alcanza con contar cuántas veces por semana te toca.

struct AttendanceBudget {
    /// Semanas de clase por semestre, deducidas de la regla de las 6 faltas.
    static let weeksPerSemester = 15
    static let allowedFraction = 0.20

    let courseID: Int
    let courseCode: String
    /// Cuántas veces por semana se cursa, según el horario cargado a mano.
    let sessionsPerWeek: Int
    /// `false` cuando no se encontró la materia en el horario y se asumió 1.
    let fromSchedule: Bool
    let absences: Int

    var totalSessions: Int { sessionsPerWeek * Self.weeksPerSemester }

    /// Faltas permitidas. Se redondea hacia abajo: 20 % de 15 son 3, no 3.5.
    var allowed: Int { Int((Double(totalSessions) * Self.allowedFraction).rounded(.down)) }

    var remaining: Int { max(0, allowed - absences) }
    var exhausted: Bool { absences >= allowed }
    var ratio: Double { allowed == 0 ? 1 : min(1, Double(absences) / Double(allowed)) }

    enum Standing {
        case holgado, ajustado, alLimite, perdido

        var label: String {
            switch self {
            case .holgado:  return "Con margen"
            case .ajustado: return "Ajustado"
            case .alLimite: return "Al límite"
            case .perdido:  return "Sin derecho a examen"
            }
        }
    }

    var standing: Standing {
        if exhausted { return .perdido }
        if remaining == 1 { return .alLimite }
        if ratio >= 0.5 { return .ajustado }
        return .holgado
    }

    /// La frase que de verdad se quiere leer.
    var sentence: String {
        if exhausted {
            return "Ya superaste el 20 % permitido (\(absences) de \(allowed)). Perdiste el derecho a examen en esta materia."
        }
        if remaining == 0 {
            return "Usaste las \(allowed) faltas permitidas. Una más y perdés el derecho a examen."
        }
        return "Te quedan \(remaining) falta\(remaining == 1 ? "" : "s") de \(allowed) — \(sessionsPerWeek) sesión\(sessionsPerWeek == 1 ? "" : "es") por semana, \(totalSessions) en el semestre."
    }
}

// MARK: - Cálculo

@MainActor
enum AttendanceBudgetIndex {

    /// Arma el presupuesto de cada materia cruzando el horario cargado a mano
    /// con las faltas registradas.
    static func budgets(courses: [MoodleCourse], store: LocalStore) -> [AttendanceBudget] {
        courses.map { course in
            let info = CourseInfo(course: course)
            let matches = store.schedule.filter { slot in
                matchesCourse(slot: slot, code: info.code, name: info.name)
            }
            let absences = store.attendance(courseId: course.id)
                .filter { $0.status == .absent }.count

            return AttendanceBudget(
                courseID: course.id,
                courseCode: info.code,
                // Sin horario cargado se asume una vez por semana: es el caso
                // conservador, el que da menos faltas permitidas.
                sessionsPerWeek: matches.isEmpty ? 1 : matches.count,
                fromSchedule: !matches.isEmpty,
                absences: absences)
        }
    }

    /// Empareja un bloque del horario con una materia.
    ///
    /// El horario se escribe a mano, así que el texto no coincide nunca exacto:
    /// se compara sin acentos ni mayúsculas, y basta con que aparezca el código
    /// ("CBM0232") o una palabra larga del nombre ("histologia").
    private static func matchesCourse(slot: ClassSlot, code: String, name: String) -> Bool {
        let haystack = DirectoryIndex.fold(slot.courseName + " " + slot.section)
        if !code.isEmpty, haystack.contains(DirectoryIndex.fold(code)) { return true }

        let words = DirectoryIndex.fold(name)
            .split(separator: " ")
            .filter { $0.count >= 5 }        // "de", "la", "ii" no distinguen nada
        return words.contains { haystack.contains($0) }
    }
}
