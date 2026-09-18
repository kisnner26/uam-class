import Foundation

// MARK: - Horario propio
//
// El horario se escribe a mano y vive solo en esta Mac. No viene de Moodle
// porque el aula virtual no publica en qué día ni a qué hora te toca cada
// clase — eso está en el portal CLASS, detrás de otro login. Escribirlo una vez
// cuesta menos que pelear con un scraper que se rompe cada semestre.

enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable {
    // Los rawValue coinciden con `Calendar.component(.weekday)` (1 = domingo),
    // así se puede preguntar "¿qué toca hoy?" sin tablas de conversión.
    case domingo = 1, lunes, martes, miercoles, jueves, viernes, sabado

    var id: Int { rawValue }

    /// Orden de lectura: la semana arranca el lunes, no el domingo.
    static let week: [Weekday] = [.lunes, .martes, .miercoles,
                                  .jueves, .viernes, .sabado, .domingo]

    static var today: Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .lunes
    }

    var label: String {
        switch self {
        case .lunes:     return "Lunes"
        case .martes:    return "Martes"
        case .miercoles: return "Miércoles"
        case .jueves:    return "Jueves"
        case .viernes:   return "Viernes"
        case .sabado:    return "Sábado"
        case .domingo:   return "Domingo"
        }
    }

    var short: String {
        switch self {
        case .lunes:     return "LUN"
        case .martes:    return "MAR"
        case .miercoles: return "MIÉ"
        case .jueves:    return "JUE"
        case .viernes:   return "VIE"
        case .sabado:    return "SÁB"
        case .domingo:   return "DOM"
        }
    }
}

/// Un bloque de clase: qué materia, con qué grupo, qué día y de qué hora a qué hora.
struct ClassSlot: Codable, Identifiable, Hashable {
    var id: UUID
    var courseName: String
    /// Sección o grupo de clase ("IS-01", "Grupo B", "T1"…). Lo que la UAM
    /// use; el campo es libre a propósito.
    var section: String
    var weekday: Weekday
    /// Aula ("B-101", "C-205"). Opcional a propósito: los horarios ya guardados
    /// no la tienen, y un campo no opcional rompería su decodificación.
    var room: String?
    /// Minutos desde medianoche. Se guardan minutos y no `Date` porque una hora
    /// de clase no tiene fecha: arrastrar una la volvería sensible a la zona
    /// horaria y al cambio de semestre.
    var startMinutes: Int
    var endMinutes: Int

    init(id: UUID = UUID(),
         courseName: String,
         section: String = "",
         weekday: Weekday,
         room: String? = nil,
         startMinutes: Int,
         endMinutes: Int) {
        self.id = id
        self.courseName = courseName
        self.section = section
        self.weekday = weekday
        self.room = room
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    var roomText: String? {
        guard let r = room?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        return r
    }

    var startText: String { Self.clock(startMinutes) }
    var endText: String   { Self.clock(endMinutes) }
    var rangeText: String { "\(startText) – \(endText)" }

    var durationText: String {
        let mins = max(0, endMinutes - startMinutes)
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// ¿Se pisa con otro bloque? Escribir un horario a mano invita a errores de
    /// dedo, y dos clases a la misma hora es el más caro de todos.
    func overlaps(_ other: ClassSlot) -> Bool {
        guard id != other.id, weekday == other.weekday else { return false }
        return startMinutes < other.endMinutes && other.startMinutes < endMinutes
    }

    /// Formato de reloj sin depender del locale del sistema: el horario de la
    /// UAM se lee en 12 horas y no queremos que cambie según la config de la Mac.
    static func clock(_ minutes: Int) -> String {
        let total = max(0, min(24 * 60 - 1, minutes))
        let h24 = total / 60
        let m = total % 60
        let suffix = h24 < 12 ? "a.m." : "p.m."
        var h = h24 % 12
        if h == 0 { h = 12 }
        return String(format: "%d:%02d %@", h, m, suffix)
    }
}
