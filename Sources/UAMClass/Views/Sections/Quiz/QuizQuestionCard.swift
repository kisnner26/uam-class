import SwiftUI

/// Una pregunta renderizada nativa. Todo lo que el usuario toca acá termina en
/// `QuizAttemptController`, que es el único que habla con Moodle.
struct QuizQuestionCard: View {
    let question: ParsedQuestion
    @ObservedObject var controller: QuizAttemptController
    var onOpenWeb: () -> Void

    @EnvironmentObject private var prefs: UserPrefs

    private var slot: Int { question.slot }
    private var readOnly: Bool { controller.readOnly }

    private var flagged: Bool {
        controller.outline.first { $0.slot == slot }?.flagged ?? question.flagged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            Divider().overlay(Palette.divider)
            statement
            answerArea
        }
        .padding(prefs.padLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(flagged ? Palette.warning : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
    }

    // MARK: Encabezado

    private var header: some View {
        HStack(spacing: Space.sm) {
            Text(question.number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(prefs.tint.brandGradient))
                .overlay(Circle().strokeBorder(Palette.rimOnDark, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 1) {
                Text(kindLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textTertiary)
                if let mark = question.maxMark {
                    Text("Vale \(Fmt.trimNumber(mark)) punto\(mark == 1 ? "" : "s")")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }

            Spacer(minLength: Space.xs)

            if readOnly, let status = question.statusLabel, !status.isEmpty {
                Pill(text: status, tone: reviewTone, compact: true)
            } else if answered {
                Pill(text: "Respondida", icon: "checkmark", tone: .success, compact: true)
            } else {
                Pill(text: "Sin responder", tone: .neutral, compact: true)
            }

            if !readOnly, question.flagFieldName != nil {
                Button {
                    controller.toggleFlag(slot: slot)
                } label: {
                    Image(systemName: flagged ? "flag.fill" : "flag")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(flagged ? Palette.warning : Palette.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.warning.opacity(flagged ? 0.14 : 0)))
                }
                .buttonStyle(.plain)
                .help(flagged ? "Quitar marca de revisión" : "Marcar para revisar después")
            }
        }
    }

    private var answered: Bool {
        controller.isAnswered(slot: slot)
    }

    private var reviewTone: Pill.Tone {
        let s = question.state ?? ""
        if s.contains("gradedright") || s.contains("mangrright") { return .success }
        if s.contains("gradedwrong") || s.contains("mangrwrong") { return .danger }
        if s.contains("partial") { return .warning }
        return .neutral
    }

    private var kindLabel: String {
        switch question.type {
        case "multichoice":  return "Opción múltiple"
        case "truefalse":    return "Verdadero o falso"
        case "shortanswer":  return "Respuesta corta"
        case "numerical", "calculated", "calculatedsimple": return "Numérica"
        case "essay":        return "Desarrollo"
        case "match", "randomsamatch": return "Emparejar"
        case "gapselect":    return "Completar"
        case "multianswer":  return "Anidada"
        default:             return question.type.capitalized
        }
    }

    // MARK: Enunciado

    private var statement: some View {
        Text(question.text)
            .font(.system(size: 14))
            .foregroundStyle(Palette.textPrimary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Área de respuesta

    @ViewBuilder
    private var answerArea: some View {
        switch question.widget {
        case .singleChoice(let field, let options):
            singleChoice(field: field, options: options)
        case .multiChoice(let options):
            multiChoice(options: options)
        case .shortText(let field, let placeholder):
            shortText(field: field, placeholder: placeholder)
        case .essay(let field, _, let format):
            essay(field: field, format: format)
        case .selects(let items):
            selects(items)
        case .unsupported(let reason):
            unsupported(reason)
        }
    }

    // Moodle mete un radio oculto con value "-1" que representa "sin responder".
    // No es una opción: si se muestra, el alumno la puede elegir sin querer.
    private func realOptions(_ options: [QuestionOption]) -> [QuestionOption] {
        options.filter { $0.value != "-1" }
    }

    private func singleChoice(field: String, options: [QuestionOption]) -> some View {
        let opts = realOptions(options)
        let current = controller.sheet.value(slot: slot, field: field)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(opts.enumerated()), id: \.element.id) { i, opt in
                ChoiceRow(letter: letter(i),
                          label: opt.label,
                          selected: current == opt.value,
                          multi: false,
                          disabled: readOnly) {
                    controller.setAnswer(slot: slot, field: field, value: opt.value)
                }
            }
            if !readOnly, current != nil {
                Button("Limpiar selección") {
                    controller.setAnswer(slot: slot, field: field, value: "-1")
                    controller.clearAnswer(slot: slot, field: field)
                }
                .buttonStyle(.plain)
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 2)
            }
        }
    }

    private func multiChoice(options: [QuestionOption]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, opt in
                let on = controller.sheet.value(slot: slot, field: opt.fieldName) == "1"
                ChoiceRow(letter: letter(i),
                          label: opt.label,
                          selected: on,
                          multi: true,
                          disabled: readOnly) {
                    if on {
                        // "0" explícito, no borrar: Moodle necesita el valor.
                        controller.setAnswer(slot: slot, field: opt.fieldName, value: "0")
                    } else {
                        controller.setAnswer(slot: slot, field: opt.fieldName, value: "1")
                    }
                }
            }
        }
    }

    private func shortText(field: String, placeholder: String?) -> some View {
        let binding = Binding<String>(
            get: { controller.sheet.value(slot: slot, field: field) ?? "" },
            set: { controller.setAnswer(slot: slot, field: field, value: $0) }
        )
        return TextField(placeholder ?? "Tu respuesta", text: binding)
            .textFieldStyle(.plain)
            .font(Type.body)
            .disabled(readOnly)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 9)
            .frame(maxWidth: 420, alignment: .leading)
            .adaptiveSurface(prefs, cornerRadius: Radius.md, elevation: .flat)
    }

    private func essay(field: String, format: String?) -> some View {
        let binding = Binding<String>(
            get: { plainFromStored(controller.sheet.value(slot: slot, field: field) ?? "",
                                   format: format) },
            set: { controller.setEssay(slot: slot, field: field, format: format, text: $0) }
        )
        return VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: binding)
                .font(Type.body)
                .scrollContentBackground(.hidden)
                .disabled(readOnly)
                .frame(minHeight: 160)
                .padding(8)
                .adaptiveSurface(prefs, cornerRadius: Radius.md, elevation: .flat)
            Text("\(binding.wrappedValue.count) caracteres")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    /// Inverso de la conversión que hace el controlador al guardar.
    private func plainFromStored(_ stored: String, format: String?) -> String {
        guard format == "1" else { return stored }
        return stored
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func selects(_ items: [QuestionWidget.SelectItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(items) { item in
                HStack(spacing: Space.sm) {
                    if !item.prompt.isEmpty {
                        Text(item.prompt)
                            .font(Type.body)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Picker("", selection: Binding<String>(
                        get: { controller.sheet.value(slot: slot, field: item.field) ?? "0" },
                        set: { controller.setAnswer(slot: slot, field: item.field, value: $0) }
                    )) {
                        ForEach(item.options) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(readOnly)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func unsupported(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Esta pregunta se responde en el visor web")
                        .font(Type.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(reason)
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            SecondaryButton(title: "Abrir el intento en el visor web",
                            icon: "safari", fullWidth: false, action: onOpenWeb)
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.warning.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.5)
        )
    }

    private func letter(_ i: Int) -> String {
        guard i < 26 else { return String(i + 1) }
        return String(UnicodeScalar(UInt8(97 + i)))
    }
}

// MARK: - Fila de opción

private struct ChoiceRow: View {
    let letter: String
    let label: String
    let selected: Bool
    let multi: Bool
    let disabled: Bool
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    if multi {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selected ? AnyShapeStyle(prefs.tint.brandGradient)
                                           : AnyShapeStyle(Palette.textPrimary.opacity(0.06)))
                            .frame(width: 18, height: 18)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(selected ? Color.clear : Palette.borderStrong,
                                          lineWidth: 1)
                            .frame(width: 18, height: 18)
                    } else {
                        Circle()
                            .fill(selected ? AnyShapeStyle(prefs.tint.brandGradient)
                                           : AnyShapeStyle(Palette.textPrimary.opacity(0.06)))
                            .frame(width: 18, height: 18)
                        Circle()
                            .strokeBorder(selected ? Color.clear : Palette.borderStrong,
                                          lineWidth: 1)
                            .frame(width: 18, height: 18)
                    }
                    if selected {
                        Image(systemName: multi ? "checkmark" : "circle.fill")
                            .font(.system(size: multi ? 10 : 7, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 1)

                Text(letter + ".")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? prefs.tint : Palette.textQuaternary)
                    .frame(width: 15, alignment: .leading)

                Text(label)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? prefs.tint.opacity(0.10)
                                   : Palette.textPrimary.opacity(hovered && !disabled ? 0.04 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(prefs.tint.opacity(selected ? 0.30 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .animation(Motion.quick, value: selected)
    }
}
