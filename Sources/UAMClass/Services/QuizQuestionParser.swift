import Foundation

// MARK: - Pregunta parseada

/// Una pregunta lista para renderizar nativo.
///
/// `baseFields` son TODOS los inputs ocultos de la pregunta, y se reenvían
/// siempre tal cual. Ahí viajan `:sequencecheck` (sin el cual Moodle descarta
/// la respuesta), los valores por defecto de "sin responder" y el flag. Las
/// respuestas del usuario se superponen encima — exactamente lo que hace un
/// navegador al enviar el formulario.
struct ParsedQuestion: Identifiable {
    let slot: Int
    let number: String
    let type: String
    let text: String
    /// HTML original, para el visor web de respaldo.
    let html: String
    let maxMark: Double?
    let state: String?
    let statusLabel: String?
    let flagged: Bool
    let flagFieldName: String?
    let baseFields: [QuizFormField]
    let widget: QuestionWidget

    var id: Int { slot }

    var isAnswerable: Bool {
        if case .unsupported = widget { return false }
        return true
    }
}

/// Opción seleccionable. `value` es el valor literal que espera Moodle.
struct QuestionOption: Identifiable, Hashable {
    let value: String
    let label: String
    /// Nombre del campo propio (checkboxes tienen uno por opción).
    let fieldName: String
    var id: String { fieldName + "=" + value }
}

enum QuestionWidget {
    /// Radios: un solo campo, varias opciones.
    case singleChoice(field: String, options: [QuestionOption])
    /// Checkboxes: un campo por opción, valor "1"/"0".
    case multiChoice(options: [QuestionOption])
    /// Campo de texto de una línea (respuesta corta, numérica).
    case shortText(field: String, placeholder: String?)
    /// Área de texto (ensayo). `formatField` guarda el formato declarado.
    case essay(field: String, formatField: String?, format: String?)
    /// Menús desplegables (emparejar, seleccionar palabra).
    case selects(items: [SelectItem])
    /// Tipo que no se puede responder de forma segura fuera del navegador.
    case unsupported(reason: String)

    struct SelectItem: Identifiable {
        let field: String
        let prompt: String
        let options: [QuestionOption]
        var id: String { field }
    }
}

// MARK: - Parser

enum QuizQuestionParser {

    /// Tipos que dependen de JavaScript o de posicionamiento en pantalla para
    /// construir la respuesta. Intentar responderlos nativamente produciría un
    /// envío incorrecto en silencio, así que se derivan al visor web.
    private static let unsupportedTypes: Set<String> = [
        "ddwtos",          // arrastrar palabras al texto
        "ddimageortext",   // arrastrar sobre imagen
        "ddmarker",        // marcadores sobre imagen
        "multianswer",     // cloze: inputs incrustados en el enunciado
        "gapselect"        // los menús van incrustados en el texto, el orden importa
    ]

    static func parse(_ payload: MoodleQuizQuestionPayload) -> ParsedQuestion {
        let root = HTMLTree.parse(payload.html)
        let que = root.first { $0.hasClass("que") } ?? root

        let type = (payload.type ?? inferType(from: que) ?? "unknown").lowercased()
        let text = (que.firstElement(class: "qtext") ?? que).innerText

        let baseFields = hiddenFields(in: que)
        let flagName = baseFields.first { $0.name.hasSuffix(":flagged") }?.name

        let widget: QuestionWidget
        if unsupportedTypes.contains(type) {
            widget = .unsupported(reason: reasonFor(type))
        } else {
            widget = buildWidget(in: que, type: type)
        }

        return ParsedQuestion(
            slot: payload.slot,
            number: payload.questionnumber ?? payload.number.map(String.init) ?? String(payload.slot),
            type: type,
            text: text,
            html: payload.html,
            maxMark: payload.maxmark,
            state: payload.state,
            statusLabel: payload.status,
            flagged: payload.flagged ?? false,
            flagFieldName: flagName,
            baseFields: baseFields,
            widget: widget
        )
    }

    // MARK: Campos ocultos

    private static func hiddenFields(in que: HTMLNode) -> [QuizFormField] {
        que.elements(tag: "input")
            .filter { ($0.attr("type") ?? "").lowercased() == "hidden" }
            .compactMap { node in
                guard let name = node.attr("name"), !name.isEmpty else { return nil }
                return QuizFormField(name: name, value: node.attr("value") ?? "")
            }
    }

    // MARK: Widget

    private static func buildWidget(in que: HTMLNode, type: String) -> QuestionWidget {
        let inputs = que.elements(tag: "input").filter {
            let t = ($0.attr("type") ?? "text").lowercased()
            return t != "hidden" && t != "submit" && t != "button" && t != "image"
        }

        let radios = inputs.filter { ($0.attr("type") ?? "").lowercased() == "radio" }
        let checks = inputs.filter { ($0.attr("type") ?? "").lowercased() == "checkbox" }
        let texts = inputs.filter {
            let t = ($0.attr("type") ?? "text").lowercased()
            return t == "text" || t == "number"
        }
        let areas = que.elements(tag: "textarea")
        let selects = que.elements(tag: "select")

        // El orden importa: un ensayo puede traer también un select de formato.
        if !radios.isEmpty {
            let field = radios.compactMap { $0.attr("name") }.first ?? ""
            // Si los radios no comparten nombre no es una elección simple.
            let names = Set(radios.compactMap { $0.attr("name") })
            guard names.count == 1 else {
                return .unsupported(reason: "La pregunta usa varios grupos de opciones.")
            }
            let options = radios.compactMap { option(from: $0, in: que) }
            guard !options.isEmpty else {
                return .unsupported(reason: "No se pudieron leer las opciones.")
            }
            return .singleChoice(field: field, options: options)
        }

        if !checks.isEmpty {
            let options = checks.compactMap { option(from: $0, in: que) }
            guard !options.isEmpty else {
                return .unsupported(reason: "No se pudieron leer las opciones.")
            }
            return .multiChoice(options: options)
        }

        if let area = areas.first, let name = area.attr("name") {
            let formatField = que.elements(tag: "input").first {
                ($0.attr("name") ?? "").hasSuffix("_answerformat")
            }
            return .essay(field: name,
                          formatField: formatField?.attr("name"),
                          format: formatField?.attr("value"))
        }

        if !selects.isEmpty {
            let items: [QuestionWidget.SelectItem] = selects.compactMap { sel in
                guard let name = sel.attr("name") else { return nil }
                let opts: [QuestionOption] = sel.elements(tag: "option").compactMap { o in
                    guard let v = o.attr("value") else { return nil }
                    let label = o.innerText
                    return QuestionOption(value: v,
                                          label: label.isEmpty ? "—" : label,
                                          fieldName: name)
                }
                guard !opts.isEmpty else { return nil }
                return QuestionWidget.SelectItem(field: name,
                                                 prompt: promptFor(select: sel),
                                                 options: opts)
            }
            guard !items.isEmpty else {
                return .unsupported(reason: "No se pudieron leer los menús.")
            }
            return .selects(items: items)
        }

        if let field = texts.first, let name = field.attr("name") {
            return .shortText(field: name, placeholder: field.attr("placeholder"))
        }

        return .unsupported(reason: "Tipo de pregunta “\(type)” sin soporte nativo.")
    }

    // MARK: Etiquetas

    /// Texto de una opción. El ancla fiable es `<label for="id-del-input">`;
    /// si falta, se cae al contenedor de la opción restándole el texto de los
    /// demás controles.
    private static func option(from input: HTMLNode, in que: HTMLNode) -> QuestionOption? {
        guard let name = input.attr("name") else { return nil }
        let value = input.attr("value") ?? "1"

        var label = ""
        if let id = input.attr("id") {
            if let lbl = que.first(where: { $0.tag == "label" && $0.attr("for") == id }) {
                label = lbl.innerText
            }
        }
        if label.isEmpty {
            // Contenedor de la opción: Moodle usa `.r0`, `.r1`, … por fila.
            if let row = input.closest(where: { n in
                n.classes.contains { $0.hasPrefix("r") && $0.count <= 3 && $0.dropFirst().allSatisfy(\.isNumber) }
            }) {
                label = row.innerText
            } else if let parent = input.parent {
                label = parent.innerText
            }
        }

        label = stripAnswerNumber(label)
        return QuestionOption(value: value,
                              label: label.isEmpty ? value : label,
                              fieldName: name)
    }

    /// Quita el "a. " / "1. " que Moodle antepone; la UI numera por su cuenta.
    private static func stripAnswerNumber(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = trimmed.range(of: #"^([a-zA-Z]|\d{1,2})[\.\)]\s+"#,
                                    options: .regularExpression) else { return trimmed }
        return String(trimmed[m.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enunciado de la fila a la que pertenece un `<select>` (emparejamiento).
    private static func promptFor(select: HTMLNode) -> String {
        if let row = select.closest(where: { $0.tag == "tr" }) {
            if let cell = row.elements(tag: "td").first {
                let t = cell.innerText
                if !t.isEmpty { return t }
            }
        }
        if let row = select.closest(where: { $0.hasClass("ablock") || $0.tag == "div" }) {
            let full = row.innerText
            let selfText = select.innerText
            let trimmed = full.replacingOccurrences(of: selfText, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    // MARK: Tipo

    private static func inferType(from que: HTMLNode) -> String? {
        // `<div class="que multichoice deferredfeedback notyetanswered">`
        let known = ["multichoice", "truefalse", "shortanswer", "numerical", "essay",
                     "match", "calculated", "calculatedsimple", "calculatedmulti",
                     "ddwtos", "ddimageortext", "ddmarker", "multianswer", "gapselect",
                     "randomsamatch", "description"]
        return que.classes.first { known.contains($0) }
    }

    private static func reasonFor(_ type: String) -> String {
        switch type {
        case "ddwtos", "ddimageortext", "ddmarker":
            return "Es una pregunta de arrastrar y soltar: la respuesta depende de dónde se sueltan los elementos, así que hay que responderla en el visor web."
        case "multianswer":
            return "Es una pregunta anidada (cloze) con campos incrustados en el enunciado. Se responde en el visor web para no equivocar el orden."
        case "gapselect":
            return "Los menús van incrustados dentro del texto y su posición importa. Se responde en el visor web."
        default:
            return "Este tipo de pregunta necesita el visor web."
        }
    }
}

// MARK: - Construcción del envío

/// Acumula las respuestas del usuario y arma el payload final.
///
/// Regla de oro: se parte SIEMPRE de los campos ocultos de la pregunta y las
/// respuestas se superponen encima. Nunca se inventa un nombre de campo.
struct QuizAnswerSheet {
    /// slot → (nombre de campo → valor)
    private(set) var answers: [Int: [String: String]] = [:]

    mutating func set(slot: Int, field: String, value: String) {
        answers[slot, default: [:]][field] = value
    }

    mutating func clear(slot: Int, field: String) {
        answers[slot]?.removeValue(forKey: field)
    }

    func value(slot: Int, field: String) -> String? {
        answers[slot]?[field]
    }

    /// Si la pregunta tiene una respuesta real.
    ///
    /// La bandera de "revisar después" se guarda en el mismo diccionario porque
    /// viaja en el mismo formulario, pero NO es una respuesta: contarla haría
    /// que marcar una pregunta la muestre como contestada en el progreso y la
    /// saque del aviso de "sin responder" antes de entregar.
    func hasAnswer(slot: Int) -> Bool {
        guard let fields = answers[slot] else { return false }
        return fields.contains { name, value in
            !name.hasSuffix(":flagged") && !value.isEmpty && value != "-1"
        }
    }

    /// Campos a enviar para las preguntas dadas.
    func fields(for questions: [ParsedQuestion]) -> [QuizFormField] {
        var out: [QuizFormField] = []
        for q in questions {
            var merged: [String: String] = [:]
            var order: [String] = []
            for f in q.baseFields {
                if merged[f.name] == nil { order.append(f.name) }
                merged[f.name] = f.value
            }
            for (name, value) in answers[q.slot] ?? [:] {
                if merged[name] == nil { order.append(name) }
                merged[name] = value
            }
            for name in order {
                out.append(QuizFormField(name: name, value: merged[name] ?? ""))
            }
        }
        return out
    }
}
