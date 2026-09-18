import Foundation

// MARK: - Entregas de tareas
//
// Subir una tarea son DOS pasos, no uno: `uploadDraft` deja el archivo en tu
// área de borradores, y `saveSubmission` lo adjunta a la asignación. Un tercero,
// `submitForGrading`, es el que le dice al docente "ya está, calificalo".
//
// Esa separación es de Moodle y no se puede saltear, pero sí importa exponerla:
// guardar sin enviar deja la entrega en borrador, y más de un estudiante perdió
// una tarea creyendo que con adjuntar alcanzaba.

extension MoodleClient {

    /// Avisos que devuelven las funciones de escritura. Vienen vacíos si todo
    /// salió bien; si traen algo, es el motivo del fracaso.
    struct AssignWarning: Decodable {
        let item: String?
        let itemid: Int?
        let warningcode: String?
        let message: String?
    }

    /// Adjunta un borrador ya subido a la asignación. Queda como BORRADOR.
    func saveSubmission(assignId: Int, draftItemId: Int) async throws {
        let warnings: [AssignWarning] = try await restForm(
            "mod_assign_save_submission",
            params: [
                "assignmentid": String(assignId),
                "plugindata[files_filemanager]": String(draftItemId)
            ],
            as: [AssignWarning].self)

        if let first = warnings.first {
            throw APIError(message: first.message ?? "Moodle rechazó la entrega.",
                           errorcode: first.warningcode)
        }
    }

    /// Envía para calificar. Después de esto, según cómo lo haya configurado el
    /// docente, puede que ya no se pueda editar.
    func submitForGrading(assignId: Int, acceptStatement: Bool = true) async throws {
        let warnings: [AssignWarning] = try await restForm(
            "mod_assign_submit_for_grading",
            params: [
                "assignmentid": String(assignId),
                "acceptsubmissionstatement": acceptStatement ? "1" : "0"
            ],
            as: [AssignWarning].self)

        if let first = warnings.first {
            throw APIError(message: first.message ?? "Moodle no aceptó el envío.",
                           errorcode: first.warningcode)
        }
    }
}
