import SwiftUI
import AppKit

/// El examinador. Ocupa toda la ventana a propósito: durante un examen no hay
/// nada más que mirar, y evita que un click al lado cierre un sheet.
struct QuizAttemptView: View {
    let session: AppState.ActiveQuiz

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @StateObject private var controller: QuizAttemptController

    @State private var showSubmitConfirm = false
    @State private var showExitConfirm = false
    @State private var showWeb = false

    init(session: AppState.ActiveQuiz, moodle: MoodleClient) {
        self.session = session
        _controller = StateObject(wrappedValue: QuizAttemptController(
            quiz: session.quiz,
            attempt: session.attempt,
            password: session.password,
            readOnly: session.review,
            moodle: moodle
        ))
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: accent, intensity: 0.5)

            VStack(spacing: 0) {
                topBar
                Divider().overlay(Palette.divider)

                switch controller.phase {
                case .loading:
                    loadingState
                case .error(let msg):
                    errorState(msg)
                case .finished:
                    finishedState
                case .ready, .submitting:
                    HSplitView {
                        navigator
                            .frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
                        questionPane
                            .frame(minWidth: 520)
                    }
                }
            }
        }
        .task { await controller.start() }
        .onDisappear { controller.stop() }
        .sheet(isPresented: $showWeb) {
            QuizWebFallback(url: webURL, title: session.quiz.name)
                .environmentObject(prefs)
        }
        .confirmationDialog("¿Entregar el examen?",
                            isPresented: $showSubmitConfirm,
                            titleVisibility: .visible) {
            Button("Entregar y terminar", role: .destructive) {
                Task { await controller.submit() }
            }
            Button("Seguir respondiendo", role: .cancel) { }
        } message: {
            Text(submitWarning)
        }
        .confirmationDialog("¿Salir del examen?",
                            isPresented: $showExitConfirm,
                            titleVisibility: .visible) {
            Button("Guardar y salir") {
                Task {
                    await controller.save()
                    close()
                }
            }
            Button("Seguir en el examen", role: .cancel) { }
        } message: {
            Text("El intento queda abierto y podés retomarlo, pero el reloj de Moodle sigue corriendo.")
        }
    }

    private var accent: Color {
        session.course.map(CourseAccent.color(for:)) ?? prefs.tint
    }

    // MARK: Barra superior

    private var topBar: some View {
        HStack(spacing: Space.md) {
            IconTile(symbol: session.review ? "doc.text.magnifyingglass" : "checkmark.square.fill",
                     tint: accent, size: 32, filled: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.quiz.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let c = session.course {
                        Text(CourseInfo(course: c).code)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                    }
                    Text(session.review
                         ? "Revisión del intento \(session.attempt.attempt ?? 1)"
                         : "Intento \(session.attempt.attempt ?? 1)")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: Space.md)

            if !session.review {
                progressPill
                saveIndicator
                if controller.remaining != nil { timerPill }
            }

            GlassIconButton(symbol: "safari", help: "Abrir en el visor web", size: 28) {
                showWeb = true
            }

            Button(session.review ? "Cerrar" : "Salir") {
                if session.review { close() } else { showExitConfirm = true }
            }
            .nativeGlassButton()
            .controlSize(.regular)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var progressPill: some View {
        let total = controller.outline.count
        let done = controller.answeredCount
        return HStack(spacing: 7) {
            AccentBar(value: total == 0 ? 0 : Double(done) / Double(total),
                      tint: accent, height: 5)
                .frame(width: 70)
            Text("\(done)/\(total)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassChip(interactive: false)
        .help("\(done) de \(total) preguntas respondidas")
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch controller.saveState {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Guardando").font(Type.micro).foregroundStyle(Palette.textTertiary)
            }
        case .saved(let at):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.success)
                Text("Guardado \(at.formatted(date: .omitted, time: .shortened))")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
        case .failed(let msg):
            // Un fallo de guardado es lo más grave que puede pasar acá, así que
            // se muestra en rojo y con reintento a un click, no como un toast.
            Button {
                Task { await controller.save() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 11))
                    Text("Sin guardar · reintentar")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.danger.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(msg)
        }
    }

    private var timerPill: some View {
        let left = controller.remaining ?? 0
        let danger = controller.isRunningOutOfTime
        return HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
            Text(Fmt.countdown(left))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(danger ? Palette.danger : Palette.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(danger ? Palette.danger.opacity(0.16)
                                          : Palette.textPrimary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(danger ? Palette.danger.opacity(0.3) : .clear,
                                        lineWidth: 0.5))
        .help(danger ? "Menos de 5 minutos. Al llegar a cero se entrega solo."
                     : "Tiempo restante del intento")
    }

    // MARK: Navegador

    private var navigator: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preguntas").labelCaps()
                .padding(.horizontal, Space.md)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xs)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 6)],
                          spacing: 6) {
                    ForEach(controller.outline) { item in
                        NavigatorCell(item: item,
                                      answered: controller.isAnswered(slot: item.slot),
                                      current: item.page == controller.currentPage,
                                      tint: accent) {
                            controller.go(toSlot: item.slot)
                        }
                    }
                }
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.sm)
            }
            .scrollContentBackground(.hidden)

            Divider().overlay(Palette.divider)

            legend
                .padding(Space.sm)
        }
        .background(.thinMaterial)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            legendRow(color: accent, text: "Respondida")
            legendRow(color: Palette.textQuaternary, text: "Sin responder")
            legendRow(color: Palette.warning, text: "Marcada")
        }
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(text).font(Type.micro).foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: Panel de preguntas

    private var questionPane: some View {
        VStack(spacing: 0) {
            if !controller.warnings.isEmpty {
                warningsBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.md) {
                        ForEach(controller.questions(onPage: controller.currentPage)) { q in
                            QuizQuestionCard(question: q,
                                             controller: controller,
                                             onOpenWeb: { showWeb = true })
                                .id(q.slot)
                        }

                        if controller.questions(onPage: controller.currentPage).isEmpty {
                            ProgressView().controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(Space.xl)
                        }
                    }
                    .padding(Space.lg)
                    .frame(maxWidth: 940, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: controller.currentPage) { _, _ in
                    proxy.scrollTo(controller.questions(onPage: controller.currentPage).first?.slot,
                                   anchor: .top)
                }
            }

            Divider().overlay(Palette.divider)
            bottomBar
        }
    }

    private var warningsBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(controller.warnings, id: \.self) { w in
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                    Text(w).font(Type.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.warning)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warning.opacity(0.10))
    }

    private var bottomBar: some View {
        HStack(spacing: Space.sm) {
            let pages = controller.pageNumbers
            let idx = pages.firstIndex(of: controller.currentPage) ?? 0

            Button {
                if idx > 0 { controller.go(toPage: pages[idx - 1]) }
            } label: {
                Label("Anterior", systemImage: "chevron.left")
            }
            .nativeGlassButton()
            .disabled(idx == 0)

            Button {
                if idx < pages.count - 1 { controller.go(toPage: pages[idx + 1]) }
            } label: {
                Label("Siguiente", systemImage: "chevron.right")
            }
            .nativeGlassButton()
            .disabled(idx >= pages.count - 1)

            Spacer()

            if !session.review {
                if !controller.unansweredSlots.isEmpty {
                    Text("\(controller.unansweredSlots.count) sin responder")
                        .font(Type.caption)
                        .foregroundStyle(Palette.warning)
                }

                PrimaryButton(title: controller.phase == .submitting ? "Entregando…" : "Entregar examen",
                              icon: "paperplane.fill",
                              loading: controller.phase == .submitting,
                              fullWidth: false) {
                    showSubmitConfirm = true
                }
                .frame(width: 190)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var submitWarning: String {
        let missing = controller.unansweredSlots.count
        var parts: [String] = []
        if missing > 0 {
            parts.append("Te quedan \(missing) pregunta\(missing == 1 ? "" : "s") sin responder.")
        }
        parts.append("Una vez entregado no vas a poder cambiar tus respuestas.")
        if case .failed = controller.saveState {
            parts.append("⚠︎ El último guardado falló. Reintentá guardar antes de entregar.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Estados

    private var loadingState: some View {
        VStack(spacing: Space.sm) {
            ProgressView().controlSize(.large)
            Text("Cargando el examen…")
                .font(Type.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: Space.md) {
            EmptyState(icon: "exclamationmark.triangle",
                       title: "No se pudo abrir el examen",
                       subtitle: msg)
            HStack(spacing: Space.sm) {
                SecondaryButton(title: "Abrir en el visor web", icon: "safari",
                                fullWidth: false) { showWeb = true }
                    .frame(width: 220)
                PrimaryButton(title: "Cerrar", fullWidth: false) { close() }
                    .frame(width: 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }

    private var finishedState: some View {
        VStack(spacing: Space.md) {
            ZStack {
                Circle().fill(Palette.success.opacity(0.14)).frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.success)
            }
            Text("Examen entregado")
                .displayStyle(24, weight: .bold)
                .foregroundStyle(Palette.textPrimary)
            Text("Moodle registró tu intento. La nota aparece en Calificaciones cuando el docente la libere.")
                .font(Type.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: Space.sm) {
                SecondaryButton(title: "Ver la revisión", icon: "doc.text.magnifyingglass",
                                fullWidth: false) {
                    state.activeQuiz = AppState.ActiveQuiz(quiz: session.quiz,
                                                           attempt: controller.attempt,
                                                           course: session.course,
                                                           password: session.password,
                                                           review: true)
                }
                .frame(width: 190)
                PrimaryButton(title: "Cerrar", fullWidth: false) { close() }
                    .frame(width: 130)
            }
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }

    // MARK: Acciones

    private func close() {
        withAnimation(Motion.spring) { state.activeQuiz = nil }
    }

    private var webURL: URL? {
        let base = state.moodleInstance.baseURL.absoluteString
        let path = session.review ? "mod/quiz/review.php" : "mod/quiz/attempt.php"
        return URL(string: "\(base)\(path)?attempt=\(session.attempt.id)")
    }
}

// MARK: - Celda del navegador

private struct NavigatorCell: View {
    let item: QuizAttemptController.QuestionOutline
    let answered: Bool
    let current: Bool
    let tint: Color
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(item.number)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(answered ? .white : Palette.textSecondary)
                .frame(width: 34, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(answered ? AnyShapeStyle(tint.brandGradient)
                                       : AnyShapeStyle(Palette.textPrimary.opacity(0.06)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(current ? Palette.textPrimary.opacity(0.55)
                                              : Color.clear,
                                      lineWidth: 1.5)
                }
                .overlay(alignment: .topTrailing) {
                    if item.flagged {
                        Circle()
                            .fill(Palette.warning)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .scaleEffect(hovered ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .help(answered ? "Pregunta \(item.number) — respondida"
                       : "Pregunta \(item.number) — sin responder")
    }
}
