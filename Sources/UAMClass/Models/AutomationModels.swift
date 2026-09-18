import SwiftUI

// MARK: - Piloto automático
//
// Una regla dice QUÉ hacer con el borrador y CUÁNDO. Nada más.
//
// La distinción que gobierna todo el diseño: **adjuntar no es entregar**.
// Adjuntar sube el archivo y lo deja en borrador dentro de Moodle — reversible,
// el docente no lo ve. Entregar lo manda a calificar y muchas veces no se puede
// deshacer. Por eso son dos acciones separadas y la segunda tiene freno propio.

struct AutomationRule: Codable, Identifiable, Hashable {

    enum Trigger: Codable, Hashable {
        /// Apenas Claude termine de escribir.
        case whenDone
        /// A una hora fija.
        case at(Date)

        var label: String {
            switch self {
            case .whenDone:  return "al terminar"
            case .at(let d): return "el " + d.formatted(.dateTime.day().month()
                                                           .hour().minute())
            }
        }
    }

    enum Action: String, Codable, Hashable {
        /// Sube y deja en BORRADOR dentro de Moodle. Reversible.
        case attach
        /// Sube y ENTREGA para calificar. Puede ser irreversible.
        case submit

        var label: String {
            switch self {
            case .attach: return "adjuntar como borrador"
            case .submit: return "entregar para calificar"
            }
        }

        var isDestructive: Bool { self == .submit }
    }

    var id: UUID = UUID()
    var assignmentID: Int
    var courseID: Int
    /// Para poder mostrar la regla sin volver a pedirle nada a Moodle.
    var assignmentName: String
    var courseCode: String
    var trigger: Trigger
    var action: Action
    /// Si quedaron marcas `[VERIFICAR: …]` en las notas, no entregar.
    ///
    /// Es el freno de mano de todo esto: entregar automáticamente un trabajo
    /// que el propio Claude marcó como dudoso es la peor forma de fallar.
    var holdOnDoubts: Bool = true
    var createdAt: Date = Date()
    /// Cuando ya se ejecutó (o se frenó), queda el resultado escrito acá.
    var outcome: String?
    var done: Bool = false

    var summary: String {
        "\(action.label) \(trigger.label)"
    }
}
