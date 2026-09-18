import Foundation

// MARK: - Secciones por plataforma
//
// Vive en Models/ (no en Views/MainWindow.swift) porque AppState la referencia
// directamente (`pendingSectionOpen: AppSection?`), y AppState es compartido
// entre macOS y iOS: el tipo tiene que estar disponible en ambos targets.

enum AppSection: String, Hashable, Identifiable, CaseIterable {
    case dashboard, materias, notasMoodle, asignaciones, examenes, asistencia, estudiar, novedades, logros, bookmarks, mensajes, directorio, estadisticas
    case personales, horario, notasClass, aranceles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:    return "Inicio"
        case .materias:     return "Materias"
        case .notasMoodle:  return "Calificaciones"
        case .asignaciones: return "Tareas"
        case .examenes:     return "Exámenes"
        case .asistencia:   return "Asistencia"
        case .bookmarks:    return "Marcadores"
        case .mensajes:     return "Mensajes"
        case .directorio:   return "Directorio"
        case .estudiar:     return "Estudiar"
        case .novedades:    return "Novedades"
        case .logros:       return "Logros"
        case .estadisticas: return "Estadísticas"
        case .personales:   return "Personales"
        case .horario:      return "Horario"
        case .notasClass:   return "Notas académicas"
        case .aranceles:    return "Aranceles"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard:    return "house.fill"
        case .materias:     return "books.vertical.fill"
        case .notasMoodle:  return "chart.bar.xaxis"
        case .asignaciones: return "checkmark.seal.fill"
        case .examenes:     return "checkmark.square.fill"
        case .asistencia:   return "person.badge.clock.fill"
        case .bookmarks:    return "bookmark.fill"
        case .mensajes:     return "bubble.left.and.bubble.right.fill"
        case .directorio:   return "person.2.fill"
        case .estudiar:     return "brain.head.profile"
        case .novedades:    return "bell.badge.fill"
        case .logros:       return "rosette"
        case .estadisticas: return "chart.pie.fill"
        case .personales:   return "person.text.rectangle.fill"
        case .horario:      return "calendar.badge.clock"
        case .notasClass:   return "graduationcap.fill"
        case .aranceles:    return "creditcard.fill"
        }
    }

    static func forPlatform(_ p: Platform) -> [AppSection] {
        switch p {
        case .moodle:      return [.dashboard, .materias, .notasMoodle, .asignaciones, .examenes, .asistencia, .horario, .estudiar, .novedades, .logros, .bookmarks, .mensajes, .directorio, .estadisticas]
        case .classPortal: return [.personales, .horario, .notasClass, .aranceles]
        }
    }
}
