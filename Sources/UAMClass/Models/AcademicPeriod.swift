import Foundation

// MARK: - Período académico
//
// Moodle codifica el semestre en el `shortname` del curso: `2026-1-LTEC03-SIS0401`
// → año 2026, primer semestre. Sin esto, la app mezcla ocho semestres de
// historia en la misma lista (las "77 asignaciones" de las que ninguna era del
// semestre en curso).
//
// OJO con el vocabulario, porque es fácil confundirse: el año de la UAM tiene
// DOS SEMESTRES, y cada semestre tiene TRES CORTES (ver `UAMGrading`). Lo que
// viene en el shortname es el semestre, no el corte.

struct AcademicPeriod: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let term: Int

    var id: String { "\(year)-\(term)" }

    /// "I Sem 2026" — compacto, para chips y menús.
    var label: String { "\(roman) Sem \(year)" }

    /// "Primer semestre · 2026"
    var longLabel: String { "\(ordinal) semestre · \(year)" }

    private var roman: String {
        switch term {
        case 1:  return "I"
        case 2:  return "II"
        case 3:  return "III"
        default: return String(term)
        }
    }

    private var ordinal: String {
        switch term {
        case 1:  return "Primer"
        case 2:  return "Segundo"
        case 3:  return "Tercer"
        default: return "\(term)°"
        }
    }

    static func < (a: AcademicPeriod, b: AcademicPeriod) -> Bool {
        a.year != b.year ? a.year < b.year : a.term < b.term
    }

    /// Extrae el período de un curso. `nil` si el shortname no sigue el patrón.
    init?(course: MoodleCourse) {
        let parts = course.shortname.split(separator: "-").map(String.init)
        guard parts.count >= 2,
              let y = Int(parts[0]), let t = Int(parts[1]),
              y > 2000, y < 2100, t > 0, t < 10
        else { return nil }
        self.year = y
        self.term = t
    }

    init(year: Int, term: Int) {
        self.year = year
        self.term = term
    }
}

// MARK: - Alcance

/// Qué semestre mira la app. Es global: si estás viendo el semestre actual, lo
/// ves en materias, tareas, notas y exámenes a la vez.
enum PeriodScope: Hashable, Codable {
    case current
    case previous
    case all
    case specific(AcademicPeriod)

    var label: String {
        switch self {
        case .current:          return "Semestre actual"
        case .previous:         return "Semestres anteriores"
        case .all:              return "Todos los semestres"
        case .specific(let p):  return p.label
        }
    }

    var shortLabel: String {
        switch self {
        case .current:          return "Actual"
        case .previous:         return "Anteriores"
        case .all:              return "Todos"
        case .specific(let p):  return p.label
        }
    }

    var symbol: String {
        switch self {
        case .current:   return "circle.fill"
        case .previous:  return "clock.arrow.circlepath"
        case .all:       return "square.stack"
        case .specific:  return "calendar"
        }
    }
}

// MARK: - Clasificación

enum PeriodIndex {

    /// Semestres presentes en la matrícula, del más nuevo al más viejo.
    static func periods(in courses: [MoodleCourse]) -> [AcademicPeriod] {
        Array(Set(courses.compactMap(AcademicPeriod.init(course:)))).sorted(by: >)
    }

    /// El semestre en curso = el más reciente que aparece en la matrícula.
    ///
    /// Se calcula desde los datos y no desde el reloj a propósito: si UAM abre
    /// el semestre tarde, o si estás mirando la app en vacaciones, la fecha de
    /// hoy mentiría sobre cuál es "tu" semestre actual.
    static func current(in courses: [MoodleCourse]) -> AcademicPeriod? {
        periods(in: courses).first
    }

    /// Filtra una lista de cursos por alcance.
    static func filter(_ courses: [MoodleCourse], scope: PeriodScope) -> [MoodleCourse] {
        guard let current = current(in: courses) else { return courses }
        switch scope {
        case .all:
            return courses
        case .current:
            return courses.filter { AcademicPeriod(course: $0) == current }
        case .previous:
            return courses.filter {
                guard let p = AcademicPeriod(course: $0) else { return false }
                return p < current
            }
        case .specific(let target):
            return courses.filter { AcademicPeriod(course: $0) == target }
        }
    }
}
