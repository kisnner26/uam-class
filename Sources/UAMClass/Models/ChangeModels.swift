import SwiftUI

// MARK: - Cambios silenciosos
//
// Moodle avisa cuando alguien PUBLICA algo, pero nunca cuando EDITA. Si el
// docente adelanta una entrega del 12 al 9, o reescribe el enunciado, o borra un
// archivo, no hay notificación, ni correo, ni marca en la interfaz. La única
// forma de enterarte es acordarte de cómo estaba antes.
//
// Eso es exactamente lo que Moodle no puede hacer y la app sí: guardar TU copia
// anterior y compararla. Un snapshot por materia, un diff cada vez que se pide,
// y un diario de lo que cambió desde la última mirada.

/// Una diferencia concreta entre dos fotos de la misma materia.
struct CourseChange: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case dueDateMoved      // lo más caro de no enterarse
        case assignmentAdded
        case assignmentRenamed
        case assignmentEdited
        case moduleAdded
        case moduleRemoved
        case fileAdded

        var symbol: String {
            switch self {
            case .dueDateMoved:      return "calendar.badge.exclamationmark"
            case .assignmentAdded:   return "plus.circle.fill"
            case .assignmentRenamed: return "pencil"
            case .assignmentEdited:  return "text.badge.checkmark"
            case .moduleAdded:       return "doc.badge.plus"
            case .moduleRemoved:     return "trash"
            case .fileAdded:         return "paperclip"
            }
        }

        /// Solo el cambio de fecha se pinta fuerte. Si todo grita, nada grita.
        var isCritical: Bool { self == .dueDateMoved }

        var label: String {
            switch self {
            case .dueDateMoved:      return "Fecha de entrega"
            case .assignmentAdded:   return "Tarea nueva"
            case .assignmentRenamed: return "Renombrada"
            case .assignmentEdited:  return "Enunciado editado"
            case .moduleAdded:       return "Material nuevo"
            case .moduleRemoved:     return "Material eliminado"
            case .fileAdded:         return "Archivo nuevo"
            }
        }
    }

    var id: String
    var courseId: Int
    var courseCode: String
    var kind: Kind
    /// Qué cambió: "Laboratorio 1", "Tarea 3"…
    var subject: String
    /// Cómo cambió, en castellano.
    var detail: String
    var detectedAt: Date
    var seen: Bool

    var tone: Color { kind.isCritical ? Palette.warning : Palette.textSecondary }
}

// MARK: - Huellas
//
// No se guarda el contenido entero, solo lo justo para detectar el cambio. Un
// snapshot liviano se puede guardar por materia sin que UserDefaults engorde.

struct AssignmentFingerprint: Codable, Hashable {
    var name: String
    var duedate: Int?
    var cutoffdate: Int?
    /// Hash del enunciado: alcanza para saber que cambió, y no guarda el texto.
    var introHash: Int
}

/// Hash ESTABLE entre lanzamientos (FNV-1a).
///
/// `hashValue` de Swift no sirve para esto: usa una semilla aleatoria por
/// proceso, así que al reabrir la app todos los enunciados parecerían haber
/// cambiado y el diario se llenaría de mentiras cada vez que arrancás.
enum StableHash {
    static func of(_ s: String) -> Int {
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 1_099_511_628_211
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
    }
}

struct ModuleFingerprint: Codable, Hashable {
    var name: String
    var fileNames: [String]
}

/// Una foto completa de una materia, tal como la viste la última vez.
struct CourseSnapshot: Codable {
    var takenAt: Date
    var assignments: [Int: AssignmentFingerprint]
    var modules: [Int: ModuleFingerprint]

    static let empty = CourseSnapshot(takenAt: .distantPast,
                                      assignments: [:], modules: [:])
}
