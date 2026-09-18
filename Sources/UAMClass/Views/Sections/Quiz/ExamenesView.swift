import SwiftUI

/// Todos los cuestionarios de todas las materias en un solo lugar.
/// Sin esto habría que entrar curso por curso a buscar dónde está el examen.
struct ExamenesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var entries: [Entry] = []
    @State private var loading = false
    @State private var scope: Scope = .disponibles
    @State private var error: String?

    enum Scope: String, CaseIterable, Identifiable, Hashable {
        case disponibles, proximos, cerrados
        var id: String { rawValue }
        var label: String {
            switch self {
            case .disponibles: return "Disponibles"
            case .proximos:    return "Próximos"
            case .cerrados:    return "Cerrados"
            }
        }
    }

    struct Entry: Identifiable {
        let quiz: MoodleQuiz
        let course: MoodleCourse
        var attempts: [MoodleQuizAttempt]
        var id: Int { quiz.id }

        var inProgress: MoodleQuizAttempt? { attempts.first(where: \.isInProgress) }
        var finishedCount: Int { attempts.filter(\.isFinished).count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if loading && entries.isEmpty {
                    Card {
                        VStack(spacing: Space.sm) {
                            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                        }
                    }
                } else if let error {
                    Card {
                        EmptyState(icon: "exclamationmark.triangle",
                                   title: "No se pudieron cargar los exámenes",
                                   subtitle: error)
                    }
                } else if filtered.isEmpty {
                    Card {
                        EmptyState(icon: emptyIcon,
                                   title: emptyTitle,
                                   subtitle: emptySubtitle)
                    }
                } else {
                    VStack(spacing: Space.sm) {
                        ForEach(filtered) { entry in
                            ExamRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task(id: state.visibleCourses.map(\.id)) { await load() }
    }

    private var header: some View {
        SectionHeader(
            title: "Exámenes",
            eyebrow: "Cuestionarios",
            subtitle: subtitle,
            trailing: AnyView(
                HStack(spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    GlassSegmented(selection: $scope,
                                   options: Scope.allCases.map { .init($0, label: $0.label) })
                }
            )
        )
    }

    private var subtitle: String {
        let open = entries.filter { $0.quiz.isOpenNow }.count
        let running = entries.filter { $0.inProgress != nil }.count
        if running > 0 {
            return "\(running) intento\(running == 1 ? "" : "s") en curso · \(open) disponible\(open == 1 ? "" : "s")"
        }
        return "\(open) disponible\(open == 1 ? "" : "s") de \(entries.count)"
    }

    private var filtered: [Entry] {
        let now = Date()
        switch scope {
        case .disponibles:
            return entries.filter { $0.quiz.isOpenNow }
                .sorted { ($0.quiz.closeDate ?? .distantFuture) < ($1.quiz.closeDate ?? .distantFuture) }
        case .proximos:
            return entries.filter { ($0.quiz.openDate ?? .distantPast) > now }
                .sorted { ($0.quiz.openDate ?? .distantFuture) < ($1.quiz.openDate ?? .distantFuture) }
        case .cerrados:
            return entries.filter { ($0.quiz.closeDate ?? .distantFuture) < now }
                .sorted { ($0.quiz.closeDate ?? .distantPast) > ($1.quiz.closeDate ?? .distantPast) }
        }
    }

    private var emptyIcon: String {
        scope == .disponibles ? "checkmark.circle" : "tray"
    }
    private var emptyTitle: String {
        switch scope {
        case .disponibles: return "Sin exámenes abiertos"
        case .proximos:    return "Sin exámenes programados"
        case .cerrados:    return "Sin exámenes cerrados"
        }
    }
    private var emptySubtitle: String {
        switch scope {
        case .disponibles: return "Ningún cuestionario está disponible en este momento."
        case .proximos:    return "No hay cuestionarios con fecha de apertura futura."
        case .cerrados:    return "Todavía no venció ningún cuestionario."
        }
    }

    // MARK: Carga

    private func load() async {
        guard !state.visibleCourses.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let resp = try await state.moodle.quizzes(courseIds: state.visibleCourses.map(\.id))
            let byCourse = Dictionary(uniqueKeysWithValues: state.visibleCourses.map { ($0.id, $0) })

            var built: [Entry] = resp.quizzes.compactMap { q in
                guard let cid = q.course, let course = byCourse[cid] else { return nil }
                return Entry(quiz: q, course: course, attempts: [])
            }

            await MainActor.run { self.entries = built }

            // Los intentos van en una segunda pasada: son una llamada por quiz y
            // no vale la pena bloquear el listado esperándolas.
            for i in built.indices {
                if let a = try? await state.moodle.quizAttempts(
                    quizId: built[i].quiz.id,
                    userId: state.moodleSiteInfo?.userid
                ) {
                    built[i].attempts = a.attempts
                    let snapshot = built
                    await MainActor.run { self.entries = snapshot }
                }
            }
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Fila

private struct ExamRow: View {
    let entry: ExamenesView.Entry

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false
    @State private var starting = false

    private var accent: Color { CourseAccent.color(for: entry.course) }
    private var quiz: MoodleQuiz { entry.quiz }

    var body: some View {
        HStack(spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 42)

            IconTile(symbol: "checkmark.square.fill", tint: accent, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(CourseInfo(course: entry.course).code)
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                    if let limit = quiz.timeLimitInterval {
                        Pill(text: Fmt.countdown(limit), icon: "timer",
                             tone: .neutral, compact: true)
                    }
                    if entry.inProgress != nil {
                        Pill(text: "En curso", icon: "record.circle",
                             tone: .warning, compact: true)
                    } else if entry.finishedCount > 0 {
                        Pill(text: "\(entry.finishedCount) entregado\(entry.finishedCount == 1 ? "" : "s")",
                             icon: "checkmark", tone: .success, compact: true)
                    }
                }

                Text(HTMLClean.plain(quiz.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                Text(scheduleText)
                    .font(Type.micro)
                    .foregroundStyle(closingSoon ? Palette.danger : Palette.textTertiary)
            }

            Spacer(minLength: Space.sm)

            Button(entry.inProgress != nil ? "Continuar" : "Abrir") {
                open()
            }
            .nativeGlassButton(prominent: entry.inProgress != nil)
            .tint(accent)
            .controlSize(.regular)
            .disabled(starting)
        }
        .padding(.horizontal, prefs.padLarge)
        .padding(.vertical, Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg, elevation: hovered ? .mid : .low)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    private var closingSoon: Bool {
        guard let c = quiz.closeDate else { return false }
        let left = c.timeIntervalSinceNow
        return left > 0 && left < 86_400
    }

    private var scheduleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .medium
        f.timeStyle = .short

        if let open = quiz.openDate, open > Date() {
            return "Abre el \(f.string(from: open))"
        }
        if let close = quiz.closeDate {
            return close < Date()
                ? "Cerró el \(f.string(from: close))"
                : "Cierra el \(f.string(from: close))"
        }
        return "Sin fecha de cierre"
    }

    /// Abre el intento en curso directo; si no hay, lleva al detalle del curso,
    /// donde están las reglas y el botón de empezar. Nunca arranca un intento
    /// nuevo desde acá: empezar un examen no puede ser un click accidental.
    private func open() {
        if let running = entry.inProgress {
            let session = AppState.ActiveQuiz(quiz: quiz,
                                              attempt: running,
                                              course: entry.course,
                                              password: nil,
                                              review: false)
            withAnimation(Motion.spring) { state.activeQuiz = session }
        } else {
            state.pendingCourseOpen = entry.course
        }
    }
}
