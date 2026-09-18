import SwiftUI
import UserNotifications

/// Ejecuta las reglas del piloto automático.
///
/// Es lo más parecido a n8n que tiene sentido acá: un disparador, una acción y
/// una condición de freno. Lo que NO hace, a propósito:
///
///  · No corre con la app cerrada. macOS no le da a una app normal un demonio
///    de fondo, y montar uno con `launchd` para subir tareas sería desmedido.
///    Si la app no está abierta a la hora fijada, la regla se ejecuta apenas
///    la abras, y te lo dice.
///  · No entrega nada si Claude dejó dudas escritas, salvo que lo desactives.
@MainActor
final class AutoPilot: ObservableObject {
    static let shared = AutoPilot()

    @Published private(set) var lastMessage: String?
    @Published private(set) var working = false

    private var timer: Timer?
    private var state: AppState?
    private let store = LocalStore.shared

    private init() {}

    /// Arranca el reloj. Se llama una vez, al montar la ventana.
    func start(state: AppState) {
        self.state = state
        guard timer == nil else { return }
        // Cada minuto alcanza: las reglas se fijan por hora, no por segundo.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick() }   // por si quedó algo vencido mientras estaba cerrada
    }

    // MARK: Disparadores

    /// El panel avisa cuando Claude terminó una tarea.
    func claudeFinished(assignmentID: Int, folder: URL) async {
        let due = store.rules(for: assignmentID).filter { $0.trigger == .whenDone }
        for rule in due {
            await execute(rule, folder: folder)
        }
    }

    /// Revisa las reglas con hora vencida.
    private func tick() async {
        let now = Date()
        for rule in store.pendingRules {
            guard case .at(let when) = rule.trigger, when <= now else { continue }
            let folder = folderFor(rule)
            guard FileManager.default.fileExists(atPath: folder.path) else {
                finish(rule, "No había borrador en la carpeta cuando llegó la hora.")
                continue
            }
            await execute(rule, folder: folder)
        }
    }

    private func folderFor(_ rule: AutomationRule) -> URL {
        // Se reconstruye la ruta con los mismos datos con que se creó.
        let stub = MoodleAssignment(id: rule.assignmentID, cmid: nil,
                                    course: rule.courseID, name: rule.assignmentName,
                                    intro: nil, duedate: nil,
                                    allowsubmissionsfromdate: nil, cutoffdate: nil,
                                    grade: nil, introattachments: nil)
        let course = state?.courses.first { $0.id == rule.courseID }
        return TaskWorkspace.folder(for: stub, course: course)
    }

    // MARK: Ejecución

    private func execute(_ rule: AutomationRule, folder: URL) async {
        guard let state else { return }
        working = true
        defer { working = false }

        let files = TaskWorkspace.deliverables(in: folder)

        guard !files.isEmpty else {
            finish(rule, "No había ningún archivo en formato entregable (.docx, .pdf…). No se subió nada.")
            return
        }

        // Freno adicional: sin notas no hay nada que revisar. Pasó en la
        // primera corrida real — la corrida se cortó, quedó el entregable sin
        // notas, y entregar eso a ciegas es justo lo que hay que evitar.
        let hasNotes = FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("NOTAS-PARA-REVISAR.md").path)
        if rule.action == .submit, rule.holdOnDoubts, !hasNotes {
            finish(rule, "Frenado: no hay NOTAS-PARA-REVISAR.md, así que la corrida quedó incompleta. Rehacela antes de entregar.")
            notify("Entrega frenada", "\(rule.courseCode): el borrador quedó incompleto.")
            return
        }

        // El freno de mano.
        if rule.action == .submit, rule.holdOnDoubts, let doubt = pendingDoubts(in: folder) {
            finish(rule, "Frenado antes de entregar: Claude dejó \(doubt) sin resolver. Revisalo y entregá a mano.")
            notify("Entrega frenada", "\(rule.courseCode): quedaron dudas sin resolver.")
            return
        }

        do {
            // Todos los archivos van al MISMO borrador: `save_submission`
            // reemplaza la entrega, no le suma.
            var itemId = 0
            for file in files {
                itemId = try await state.moodle.uploadDraft(fileURL: file, itemId: itemId)
            }
            try await state.moodle.saveSubmission(assignId: rule.assignmentID,
                                                  draftItemId: itemId)

            if rule.action == .submit {
                try await state.moodle.submitForGrading(assignId: rule.assignmentID)
                finish(rule, "Entregado para calificar (\(files.count) archivo\(files.count == 1 ? "" : "s")).")
                notify("Tarea entregada", "\(rule.courseCode) — \(rule.assignmentName)")
            } else {
                finish(rule, "Adjuntado como borrador (\(files.count) archivo\(files.count == 1 ? "" : "s")). Falta que la entregues.")
                notify("Borrador adjuntado", "\(rule.courseCode) — falta entregarla vos")
            }
        } catch {
            let msg = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
            finish(rule, "Falló: \(msg)")
            notify("No se pudo subir", msg)
        }
    }

    /// Cuántas marcas `[VERIFICAR: …]` quedaron sin resolver.
    private func pendingDoubts(in folder: URL) -> String? {
        var count = 0
        for file in TaskWorkspace.outputs(in: folder) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            count += text.components(separatedBy: "[VERIFICAR").count - 1
        }
        guard count > 0 else { return nil }
        return "\(count) punto\(count == 1 ? "" : "s") marcado\(count == 1 ? "" : "s") como [VERIFICAR:]"
    }

    private func finish(_ rule: AutomationRule, _ outcome: String) {
        store.completeRule(rule.id, outcome: outcome)
        lastMessage = "\(rule.courseCode): \(outcome)"
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: content, trigger: nil))
    }
}
