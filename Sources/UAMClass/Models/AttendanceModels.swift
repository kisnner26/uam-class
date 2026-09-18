import SwiftUI

// MARK: - Asistencia
//
// Dos mundos que conviven:
//
//  · El registro LOCAL (esto). Siempre funciona, es tuyo, y no depende de que
//    UAM tenga instalado nada. Sirve para llevar tu propia cuenta de a cuántas
//    clases fuiste.
//  · El plugin `mod_attendance` de Moodle, que es de TERCEROS y puede no estar
//    instalado. Cuando existe, la app lo detecta y muestra las sesiones reales
//    que abrió el docente.

enum AttendanceStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case present, late, excused, absent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .present: return "Presente"
        case .late:    return "Tarde"
        case .excused: return "Justificada"
        case .absent:  return "Ausente"
        }
    }

    var symbol: String {
        switch self {
        case .present: return "checkmark"
        case .late:    return "clock"
        case .excused: return "doc.text"
        case .absent:  return "xmark"
        }
    }

    var tone: Color {
        switch self {
        case .present: return Palette.success
        case .late:    return Palette.warning
        case .excused: return Palette.textSecondary
        case .absent:  return Palette.danger
        }
    }

    /// "Tarde" cuenta como asistencia para el porcentaje; "justificada" no
    /// suma ni resta en la mayoría de reglamentos, pero acá la contamos aparte
    /// para no inflar el número.
    var countsAsPresent: Bool {
        self == .present || self == .late
    }
}

struct AttendanceRecord: Codable, Identifiable, Hashable {
    let courseId: Int
    /// Normalizado a medianoche: un registro por curso y día.
    let day: Date
    var status: AttendanceStatus
    var note: String?

    var id: String { "\(courseId)-\(day.timeIntervalSince1970)" }
}
