import Foundation

/// Plataformas que soporta la app.
enum Platform: String, Hashable, CaseIterable, Identifiable, Codable {
    case moodle       = "moodle"       // UAM Virtual (Moodle)
    case classPortal  = "class"        // CLASS Portales (ASP.NET)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moodle:      return "UAM Virtual"
        case .classPortal: return "UAM Class"
        }
    }

    var subtitle: String {
        switch self {
        case .moodle:      return "Aula virtual · Moodle"
        case .classPortal: return "Registro académico"
        }
    }

    var description: String {
        switch self {
        case .moodle:
            return "Materias, asignaciones, calificaciones y recursos de tus cursos."
        case .classPortal:
            return "Horario oficial, notas académicas y estado de aranceles."
        }
    }

    var symbol: String {
        switch self {
        case .moodle:      return "graduationcap"
        case .classPortal: return "building.columns"
        }
    }
}
