import Foundation
import SwiftUI

// MARK: - Controlador de intento
//
// Reglas de diseño, todas por la misma razón (es un examen con nota real):
//
//  · Nunca se pierde una respuesta en silencio. Si un guardado falla, el estado
//    queda visible y se reintenta; no se finge éxito.
//  · El envío final es explícito y confirmado. Lo único que envía solo es el
//    vencimiento del tiempo, y va marcado con `timeup` como espera Moodle.
//  · Ante cualquier duda, la salida al navegador está siempre a mano.

@MainActor
final class QuizAttemptController: ObservableObject {

    enum SaveState: Equatable {
        case idle
        case saving
        case saved(Date)
        case failed(String)
    }

    enum Phase: Equatable {
        case loading
        case ready
        case submitting
        case finished
        case error(String)
    }

    // MARK: Entrada

    let quiz: MoodleQuiz
    private(set) var attempt: MoodleQuizAttempt
    let password: String?
    let readOnly: Bool
    private let moodle: MoodleClient

    // MARK: Estado publicado

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var saveState: SaveState = .idle

    /// Todas las preguntas del intento, en orden de slot.
    @Published private(set) var outline: [QuestionOutline] = []
    /// Preguntas ya cargadas, por página.
    @Published private(set) var loadedPages: [Int: [ParsedQuestion]] = [:]
    @Published var currentPage: Int = 0
    @Published private(set) var sheet = QuizAnswerSheet()
    @Published private(set) var remaining: TimeInterval?
    @Published private(set) var warnings: [String] = []

    struct QuestionOutline: Identifiable, Hashable {
        let slot: Int
        let page: Int
        let number: String
        var state: String
        var flagged: Bool
        var id: Int { slot }

        var isAnswered: Bool { state != "todo" && state != "invalid" && !state.isEmpty }
    }

    // MARK: Internos

    private var autosaveTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var deadline: Date?
    private var ticks = 0
    /// Se marca cuando hay cambios sin confirmar en el servidor.
    private var dirty = false

    init(quiz: MoodleQuiz,
         attempt: MoodleQuizAttempt,
         password: String?,
         readOnly: Bool,
         moodle: MoodleClient) {
        self.quiz = quiz
        self.attempt = attempt
        self.password = password
        self.readOnly = readOnly
        self.moodle = moodle
    }

    deinit {
        autosaveTask?.cancel()
        tickTask?.cancel()
    }

    // MARK: Ciclo de vida

    func start() async {
        phase = .loading
        do {
            if readOnly {
                try await loadReview()
            } else {
                try await loadOutline()
                try await loadPage(attempt.currentpage ?? 0)
                currentPage = attempt.currentpage ?? 0
                startClock()
            }
            phase = .ready
        } catch {
            phase = .error(friendly(error))
        }
        await moodle.markAttemptViewed(attemptId: attempt.id, page: currentPage)
    }

    func stop() {
        autosaveTask?.cancel()
        tickTask?.cancel()
    }

    // MARK: Carga

    private func loadOutline() async throws {
        let summary = try await moodle.attemptSummary(attemptId: attempt.id, password: password)
        collectWarnings(summary.warnings)
        outline = summary.questions
            .sorted { $0.slot < $1.slot }
            .map { q in
                QuestionOutline(slot: q.slot,
                                page: q.page ?? 0,
                                number: q.questionnumber ?? q.number.map(String.init) ?? String(q.slot),
                                state: q.state ?? "todo",
                                flagged: q.flagged ?? false)
            }
    }

    private func loadReview() async throws {
        let review = try await moodle.attemptReview(attemptId: attempt.id, page: -1)
        collectWarnings(review.warnings)
        attempt = review.attempt
        let parsed = review.questions.sorted { $0.slot < $1.slot }.map(QuizQuestionParser.parse)
        loadedPages = [0: parsed]
        outline = parsed.map {
            QuestionOutline(slot: $0.slot, page: 0, number: $0.number,
                            state: $0.state ?? "", flagged: $0.flagged)
        }
        currentPage = 0
    }

    @discardableResult
    func loadPage(_ page: Int) async throws -> [ParsedQuestion] {
        if let cached = loadedPages[page] { return cached }
        let data = try await moodle.attemptData(attemptId: attempt.id,
                                                page: page,
                                                password: password)
        collectWarnings(data.warnings)
        if let msgs = data.messages, !msgs.isEmpty {
            warnings.append(contentsOf: msgs)
        }
        let parsed = data.questions.map(QuizQuestionParser.parse)
        loadedPages[page] = parsed
        seedAnswers(from: parsed)
        return parsed
    }

    /// Reconstruye en la hoja lo que el servidor ya tenía guardado, para que al
    /// volver a una página las respuestas aparezcan marcadas.
    private func seedAnswers(from questions: [ParsedQuestion]) {
        let root = { (html: String) in HTMLTree.parse(html) }
        for q in questions {
            let tree = root(q.html)
            switch q.widget {
            case .singleChoice(let field, _):
                if let checked = tree.elements(tag: "input").first(where: {
                    ($0.attr("type") ?? "").lowercased() == "radio"
                        && $0.attr("name") == field
                        && $0.attr("checked") != nil
                        && ($0.attr("value") ?? "") != "-1"
                }), let v = checked.attr("value") {
                    sheet.set(slot: q.slot, field: field, value: v)
                }
            case .multiChoice(let options):
                for o in options {
                    let isChecked = tree.elements(tag: "input").contains {
                        ($0.attr("type") ?? "").lowercased() == "checkbox"
                            && $0.attr("name") == o.fieldName
                            && $0.attr("checked") != nil
                    }
                    if isChecked { sheet.set(slot: q.slot, field: o.fieldName, value: "1") }
                }
            case .shortText(let field, _):
                if let input = tree.elements(tag: "input").first(where: { $0.attr("name") == field }),
                   let v = input.attr("value"), !v.isEmpty {
                    sheet.set(slot: q.slot, field: field, value: v)
                }
            case .essay(let field, _, _):
                if let area = tree.elements(tag: "textarea").first(where: { $0.attr("name") == field }) {
                    let v = area.innerText
                    if !v.isEmpty { sheet.set(slot: q.slot, field: field, value: v) }
                }
            case .selects(let items):
                for item in items {
                    guard let sel = tree.elements(tag: "select")
                        .first(where: { $0.attr("name") == item.field }) else { continue }
                    if let picked = sel.elements(tag: "option")
                        .first(where: { $0.attr("selected") != nil }),
                       let v = picked.attr("value"), v != "0" {
                        sheet.set(slot: q.slot, field: item.field, value: v)
                    }
                }
            case .unsupported:
                break
            }
        }
    }

    func questions(onPage page: Int) -> [ParsedQuestion] {
        loadedPages[page] ?? []
    }

    var pageNumbers: [Int] {
        Array(Set(outline.map(\.page))).sorted()
    }

    var isLastPage: Bool {
        currentPage >= (pageNumbers.last ?? 0)
    }

    func go(toPage page: Int) {
        Task {
            do {
                try await loadPage(page)
                currentPage = page
                await moodle.markAttemptViewed(attemptId: attempt.id, page: page)
            } catch {
                saveState = .failed(friendly(error))
            }
        }
    }

    func go(toSlot slot: Int) {
        guard let entry = outline.first(where: { $0.slot == slot }) else { return }
        go(toPage: entry.page)
    }

    // MARK: Respuestas

    func setAnswer(slot: Int, field: String, value: String) {
        guard !readOnly else { return }
        sheet.set(slot: slot, field: field, value: value)
        markAnsweredLocally(slot: slot)
        scheduleAutosave()
    }

    func clearAnswer(slot: Int, field: String) {
        guard !readOnly else { return }
        sheet.clear(slot: slot, field: field)
        markAnsweredLocally(slot: slot)
        scheduleAutosave()
    }

    /// Texto de ensayo. Moodle declara el formato en un campo oculto; si es
    /// HTML hay que escapar y convertir los saltos, o el texto llega en un
    /// solo párrafo con las comillas rotas.
    func setEssay(slot: Int, field: String, format: String?, text: String) {
        let value: String
        if format == "1" {   // FORMAT_HTML
            let escaped = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            value = escaped.replacingOccurrences(of: "\n", with: "<br>")
        } else {
            value = text
        }
        setAnswer(slot: slot, field: field, value: value)
    }

    private func markAnsweredLocally(slot: Int) {
        guard let idx = outline.firstIndex(where: { $0.slot == slot }) else { return }
        outline[idx].state = isAnswered(slot: slot) ? "complete" : "todo"
    }

    /// Si una pregunta cuenta como respondida.
    ///
    /// No se puede decidir mirando el valor a secas: en verdadero/falso "0" es
    /// una respuesta legítima (Falso), mientras que en una casilla "0" significa
    /// desmarcada y en un desplegable "0" es el "Elegir…". Cada widget tiene su
    /// propia noción de vacío.
    func isAnswered(slot: Int) -> Bool {
        guard let q = currentQuestion(slot: slot) else {
            // Página no cargada todavía: vale lo que dijo el servidor.
            return outline.first { $0.slot == slot }?.isAnswered ?? false
        }
        switch q.widget {
        case .singleChoice(let field, _):
            let v = sheet.value(slot: slot, field: field)
            return v != nil && v != "-1" && !(v!.isEmpty)
        case .multiChoice(let options):
            return options.contains { sheet.value(slot: slot, field: $0.fieldName) == "1" }
        case .shortText(let field, _):
            return !(sheet.value(slot: slot, field: field) ?? "").isEmpty
        case .essay(let field, _, _):
            return !(sheet.value(slot: slot, field: field) ?? "").isEmpty
        case .selects(let items):
            return items.contains { item in
                let v = sheet.value(slot: slot, field: item.field)
                return v != nil && v != "0" && !(v!.isEmpty)
            }
        case .unsupported:
            // No se puede responder acá, así que manda el estado del servidor.
            return outline.first { $0.slot == slot }?.isAnswered ?? false
        }
    }

    func toggleFlag(slot: Int) {
        guard let q = currentQuestion(slot: slot), let field = q.flagFieldName else { return }
        guard let idx = outline.firstIndex(where: { $0.slot == slot }) else { return }
        let newValue = !outline[idx].flagged
        outline[idx].flagged = newValue
        setAnswer(slot: slot, field: field, value: newValue ? "1" : "0")
    }

    private func currentQuestion(slot: Int) -> ParsedQuestion? {
        loadedPages.values.flatMap { $0 }.first { $0.slot == slot }
    }

    // MARK: Guardado

    private func scheduleAutosave() {
        dirty = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Guarda sin cerrar el intento. Idempotente y seguro de llamar seguido.
    func save() async {
        guard !readOnly, dirty else { return }
        let fields = sheet.fields(for: allLoadedQuestions())
        guard !fields.isEmpty else { return }

        saveState = .saving
        do {
            let r = try await moodle.saveAttempt(attemptId: attempt.id,
                                                 data: fields,
                                                 password: password)
            collectWarnings(r.warnings)
            dirty = false
            saveState = .saved(Date())
        } catch {
            // No se limpia `dirty`: el próximo intento reenvía todo.
            saveState = .failed(friendly(error))
        }
    }

    private func allLoadedQuestions() -> [ParsedQuestion] {
        loadedPages.keys.sorted().flatMap { loadedPages[$0] ?? [] }
    }

    // MARK: Envío final

    /// Cierra el intento y lo manda a calificar. Irreversible.
    func submit(timeUp: Bool = false) async {
        guard !readOnly else { return }
        phase = .submitting
        do {
            // Un guardado previo deja las respuestas en el servidor aunque el
            // process falle a mitad de camino.
            await save()
            let fields = sheet.fields(for: allLoadedQuestions())
            let r = try await moodle.processAttempt(attemptId: attempt.id,
                                                    data: fields,
                                                    finish: true,
                                                    timeUp: timeUp,
                                                    password: password)
            collectWarnings(r.warnings)
            stop()
            phase = .finished
        } catch {
            phase = .ready
            saveState = .failed("No se pudo entregar: \(friendly(error))")
        }
    }

    // MARK: Reloj

    /// Arranca siempre, aunque el examen no tenga tiempo límite: el mismo tick
    /// mueve el reintento de guardado.
    private func startClock() {
        if let limit = quiz.timeLimitInterval, let started = attempt.startDate {
            deadline = started.addingTimeInterval(limit)
        } else {
            deadline = nil
            remaining = nil
        }
        tick()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await MainActor.run { self.tick() }
            }
        }
    }

    private func tick() {
        ticks += 1

        // Red de seguridad: si quedó algo sin confirmar (típicamente porque un
        // guardado falló por red), se reintenta solo cada 20s. Sin esto, un
        // corte breve puede dejar respuestas solo en pantalla hasta el envío.
        if ticks % 20 == 0, dirty, saveState != .saving {
            Task { await self.save() }
        }

        guard let deadline else { return }
        let left = deadline.timeIntervalSinceNow
        remaining = max(0, left)
        if left <= 0 {
            tickTask?.cancel()
            Task { await self.submit(timeUp: true) }
        }
    }

    var isRunningOutOfTime: Bool {
        guard let r = remaining else { return false }
        return r <= 300
    }

    // MARK: Progreso

    var answeredCount: Int {
        outline.filter { isAnswered(slot: $0.slot) }.count
    }

    var unansweredSlots: [Int] {
        outline.filter { !isAnswered(slot: $0.slot) }.map(\.slot)
    }

    // MARK: Utilidades

    private func collectWarnings(_ list: [MoodleWarning]?) {
        guard let list, !list.isEmpty else { return }
        let msgs = list.compactMap { $0.message }.filter { !$0.isEmpty }
        for m in msgs where !warnings.contains(m) { warnings.append(m) }
    }

    private func friendly(_ error: Error) -> String {
        if let api = error as? MoodleClient.APIError { return api.message }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Sin conexión con Moodle. Tus respuestas siguen en pantalla; se reintenta solo."
        }
        return error.localizedDescription
    }
}
