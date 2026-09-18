import SwiftUI

// MARK: - Consultas (mod_choice)

/// Una consulta: una pregunta, varias opciones, una respuesta.
///
/// Es el caso simple y se resuelve entero dentro de la app: se ven las opciones
/// con sus cupos, se vota, y se puede cambiar el voto si el docente lo permitió.
struct ChoiceInspector: View {
    let module: MoodleModule
    let course: MoodleCourse

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var choice: MoodleChoice?
    @State private var options: [MoodleChoiceOption] = []
    @State private var picked: Int?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var justVoted = false

    private var alreadyVoted: Bool { options.contains { $0.checked == true } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if loading {
                    Card { SkeletonRow() }
                } else if let choice {
                    if !choice.cleanIntro.isEmpty {
                        Card {
                            Text(choice.cleanIntro)
                                .font(Type.body)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !choice.isOpen {
                        note("Esta consulta está cerrada.", tone: Palette.warning)
                    }

                    optionsList

                    if let error { note(error, tone: Palette.danger) }

                    actions(choice)
                } else {
                    EmptyState(icon: "checklist",
                               title: "No se pudo cargar la consulta",
                               subtitle: error ?? "Moodle no devolvió datos para esta actividad.")
                }
            }
            .padding(Space.md)
        }
        .task { await load() }
    }

    private var optionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, opt in
                let isPicked = picked == opt.id || (picked == nil && opt.checked == true)
                Button {
                    guard choice?.isOpen == true, !opt.isFull || opt.checked == true else { return }
                    SoundKit.shared.play(.select)
                    picked = opt.id
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: isPicked ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isPicked ? prefs.tint : Palette.textQuaternary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.cleanText)
                                .font(Type.body)
                                .foregroundStyle(Palette.textPrimary)
                            if let count = opt.countanswers {
                                Text(cupoText(opt, count: count))
                                    .font(Type.micro)
                                    .foregroundStyle(opt.isFull ? Palette.warning
                                                                : Palette.textQuaternary)
                            }
                        }
                        Spacer(minLength: 0)
                        if opt.checked == true {
                            Pill(text: "Tu voto", tone: .accent, compact: true)
                        }
                    }
                    .padding(.horizontal, prefs.padLarge)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(opt.isFull && opt.checked != true)
                .opacity(opt.isFull && opt.checked != true ? 0.5 : 1)

                if i < options.count - 1 {
                    Divider().overlay(Palette.divider).padding(.leading, prefs.padLarge)
                }
            }
        }
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    private func cupoText(_ opt: MoodleChoiceOption, count: Int) -> String {
        if let max = opt.maxanswers, max > 0 {
            return "\(count) de \(max) lugares"
        }
        return "\(count) respuesta\(count == 1 ? "" : "s")"
    }

    private func actions(_ choice: MoodleChoice) -> some View {
        HStack(spacing: Space.xs) {
            if justVoted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                    Text("Voto registrado")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if alreadyVoted && choice.allowupdate == true {
                Button("Quitar mi voto") {
                    Task { await removeVote() }
                }
                .nativeGlassButton()
                .controlSize(.small)
                .disabled(busy)
            }
            Button(alreadyVoted ? "Cambiar voto" : "Votar") {
                Task { await vote() }
            }
            .nativeGlassButton(prominent: true)
            .tint(prefs.tint)
            .controlSize(.small)
            .disabled(busy || picked == nil || !choice.isOpen
                      || (alreadyVoted && choice.allowupdate != true))
            if busy { ProgressView().controlSize(.small) }
        }
    }

    private func note(_ text: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(tone)
            Text(text).font(Type.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(tone.opacity(0.10)))
    }

    // MARK: Datos

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let all = try await state.moodle.choices(courseIds: [course.id])
            // `instance` del módulo es el id de la consulta, no el del módulo.
            choice = all.choices.first { $0.id == module.instance }
                  ?? all.choices.first { $0.coursemodule == module.id }
            if let c = choice {
                options = try await state.moodle.choiceOptions(choiceId: c.id)
                picked = options.first { $0.checked == true }?.id
            }
            error = nil
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func vote() async {
        guard let c = choice, let opt = picked else { return }
        busy = true; defer { busy = false }
        do {
            try await state.moodle.submitChoice(choiceId: c.id, optionIds: [opt])
            justVoted = true
            SoundKit.shared.play(.confirm)
            options = try await state.moodle.choiceOptions(choiceId: c.id)
            error = nil
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func removeVote() async {
        guard let c = choice else { return }
        busy = true; defer { busy = false }
        try? await state.moodle.deleteChoiceResponse(choiceId: c.id)
        options = (try? await state.moodle.choiceOptions(choiceId: c.id)) ?? options
        picked = nil
        justVoted = false
    }
}

// MARK: - Encuestas (mod_feedback)

/// Una encuesta de varias preguntas.
///
/// Alcance deliberadamente parcial: se responden desde la app los tipos de
/// campo de UNA sola respuesta (texto corto, texto largo, numérico y opción
/// única). Las de casillas múltiples se muestran pero se derivan a Moodle,
/// porque su codificación de respuestas es distinta y sin poder probarla contra
/// el servidor prefiero no adivinarla: una encuesta enviada mal no se puede
/// deshacer.
struct FeedbackInspector: View {
    let module: MoodleModule
    let course: MoodleCourse

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var feedback: MoodleFeedback?
    @State private var items: [MoodleFeedbackItem] = []
    @State private var answers: [Int: String] = [:]
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var completed = false

    private var unsupported: [MoodleFeedbackItem] {
        items.filter { !$0.isSupported && !$0.isDisplayOnly }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if loading {
                    Card { SkeletonRow() }
                } else if completed {
                    Card {
                        EmptyState(icon: "checkmark.seal.fill",
                                   title: "Encuesta enviada",
                                   subtitle: "Gracias. Tu respuesta quedó registrada en Moodle.")
                    }
                } else if let fb = feedback {
                    if !fb.cleanIntro.isEmpty {
                        Card {
                            Text(fb.cleanIntro)
                                .font(Type.body)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if fb.isAnonymous {
                        infoNote("Esta encuesta es anónima: tu nombre no viaja con las respuestas.")
                    }

                    ForEach(items.filter { !$0.isDisplayOnly }, id: \.id) { item in
                        questionCard(item)
                    }

                    if !unsupported.isEmpty {
                        infoNote("\(unsupported.count) pregunta\(unsupported.count == 1 ? "" : "s") de selección múltiple solo se puede\(unsupported.count == 1 ? "" : "n") responder en Moodle. Usá el botón de abajo: se abre con tu sesión ya iniciada.")
                    }
                    if let error { errorNote(error) }
                    footer(fb)
                } else {
                    EmptyState(icon: "list.clipboard",
                               title: "No se pudo cargar la encuesta",
                               subtitle: error ?? "Moodle no devolvió datos para esta actividad.")
                }
            }
            .padding(Space.md)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func questionCard(_ item: MoodleFeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 5) {
                Text(item.cleanName)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.required == true {
                    Text("obligatoria")
                        .font(Type.micro)
                        .foregroundStyle(Palette.danger)
                }
            }

            switch item.typ {
            case "textfield", "numeric":
                TextField(item.typ == "numeric" ? "Un número" : "Tu respuesta",
                          text: binding(item))
                    .textFieldStyle(.roundedBorder)
                    .font(Type.body)
            case "textarea":
                TextEditor(text: binding(item))
                    .font(Type.body)
                    .frame(height: 90)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.045)))
            case "multichoice" where item.isSupported:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(item.choices.enumerated()), id: \.offset) { idx, label in
                        // Moodle numera las opciones desde 1, no desde 0.
                        let value = String(idx + 1)
                        Button {
                            SoundKit.shared.play(.select)
                            answers[item.id] = value
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: answers[item.id] == value
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(answers[item.id] == value
                                                     ? prefs.tint : Palette.textQuaternary)
                                Text(label)
                                    .font(Type.body)
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            default:
                Text("Este tipo de pregunta se responde en Moodle.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    private func binding(_ item: MoodleFeedbackItem) -> Binding<String> {
        Binding(get: { answers[item.id] ?? "" },
                set: { answers[item.id] = $0 })
    }

    private func footer(_ fb: MoodleFeedback) -> some View {
        HStack(spacing: Space.xs) {
            Button {
                if let cm = fb.coursemodule ?? module.id as Int? {
                    MoodleOpener.shared.open(path: "mod/feedback/view.php?id=\(cm)",
                                             state: state)
                }
            } label: {
                Label("Abrir en Moodle", systemImage: "safari")
                    .font(.system(size: 12, weight: .medium))
            }
            .nativeGlassButton()
            .controlSize(.small)

            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button("Enviar respuestas") { Task { await submit(fb) } }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
                .disabled(busy || answers.isEmpty)
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11)).foregroundStyle(prefs.tint)
            Text(text).font(Type.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(prefs.tint.opacity(0.09)))
    }

    private func errorNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Palette.danger)
            Text(text).font(Type.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.danger.opacity(0.10)))
    }

    // MARK: Datos

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let all = try await state.moodle.feedbacks(courseIds: [course.id])
            feedback = all.feedbacks.first { $0.id == module.instance }
                    ?? all.feedbacks.first { $0.coursemodule == module.id }
            if let fb = feedback {
                items = try await state.moodle.feedbackPage(feedbackId: fb.id, page: 0).items
            }
            error = nil
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func submit(_ fb: MoodleFeedback) async {
        busy = true; defer { busy = false }
        let payload: [(name: String, value: String)] = items.compactMap { item in
            guard item.isSupported, let v = answers[item.id],
                  !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (item.responseKey, v)
        }
        guard !payload.isEmpty else {
            error = "No hay respuestas para enviar."
            return
        }
        do {
            let result = try await state.moodle.submitFeedbackPage(
                feedbackId: fb.id, page: 0, responses: payload)
            if let w = result.warnings?.first, let msg = w.message {
                error = msg
            } else {
                completed = result.completed ?? true
                SoundKit.shared.play(.confirm)
                error = nil
            }
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }
}
