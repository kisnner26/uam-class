import SwiftUI
import AppKit

/// Pantalla previa al examen: reglas, intentos anteriores y el botón de entrar.
/// Deliberadamente sobria — acá se toma la decisión de empezar algo que no se
/// puede deshacer, así que la información va antes que la decoración.
struct QuizInspector: View {
    let module: MoodleModule
    let course: MoodleCourse

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var quiz: MoodleQuiz?
    @State private var attempts: [MoodleQuizAttempt] = []
    @State private var access: MoodleQuizAccessInfo?
    @State private var attemptAccess: MoodleAttemptAccessInfo?
    @State private var loading = true
    @State private var error: String?
    @State private var starting = false
    @State private var password = ""
    @State private var askPassword = false

    private var accent: Color { CourseAccent.color(for: course) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if loading {
                    loadingBlock
                } else if let error {
                    errorBlock(error)
                } else if let quiz {
                    rulesCard(quiz)
                    blockersCard
                    attemptsCard(quiz)
                    actionRow(quiz)
                } else {
                    EmptyState(icon: "checkmark.square",
                               title: "Sin datos del cuestionario",
                               subtitle: "Moodle no devolvió información para este módulo.")
                }
            }
            .padding(Space.md)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .alert("Contraseña del cuestionario", isPresented: $askPassword) {
            SecureField("Contraseña", text: $password)
            Button("Empezar") { Task { await start() } }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Este examen está protegido. Pedísela al docente si no la tenés.")
        }
    }

    // MARK: Bloques

    private var loadingBlock: some View {
        Card {
            VStack(spacing: Space.sm) {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
        }
    }

    private func errorBlock(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Card {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No se pudo leer el cuestionario")
                            .font(Type.bodyBold)
                        Text(msg)
                            .font(Type.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            openInBrowser
        }
    }

    private func rulesCard(_ quiz: MoodleQuiz) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                BlockHeader(icon: "list.bullet.rectangle", title: "Reglas del examen")

                if !quiz.cleanIntro.isEmpty {
                    Text(quiz.cleanIntro)
                        .font(Type.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Palette.divider)
                }

                rule("clock", "Tiempo límite",
                     quiz.timeLimitInterval.map { Fmt.countdown($0) + " por intento" } ?? "Sin límite")
                rule("arrow.counterclockwise", "Intentos permitidos",
                     (quiz.attempts ?? 0) == 0 ? "Ilimitados" : "\(quiz.attempts!)")
                if let open = quiz.openDate {
                    rule("calendar.badge.clock", "Abre",
                         open.formatted(date: .abbreviated, time: .shortened))
                }
                if let close = quiz.closeDate {
                    rule("calendar.badge.exclamationmark", "Cierra",
                         close.formatted(date: .abbreviated, time: .shortened),
                         tone: close < Date() ? .danger : .neutral)
                }
                if let g = quiz.grade, g > 0 {
                    rule("star.circle", "Nota máxima", Fmt.trimNumber(g))
                }
                if quiz.requiresPassword {
                    rule("lock.fill", "Protegido", "Requiere contraseña", tone: .warning)
                }
            }
        }
    }

    private func rule(_ icon: String, _ label: String, _ value: String,
                      tone: Pill.Tone = .neutral) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 16)
            Text(label)
                .font(Type.caption)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.sm)
            switch tone {
            case .neutral:
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            default:
                Pill(text: value, tone: tone, compact: true)
            }
        }
    }

    @ViewBuilder
    private var blockersCard: some View {
        let reasons = (access?.preventaccessreasons ?? [])
            + (attemptAccess?.preventnewattemptreasons ?? [])
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(reasons, id: \.self) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11))
                            .symbolRenderingMode(.hierarchical)
                        Text(HTMLClean.plain(r))
                            .font(Type.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.warning)
                }
            }
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.warning.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.5)
            )
        }
    }

    private func attemptsCard(_ quiz: MoodleQuiz) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                BlockHeader(icon: "clock.arrow.circlepath", title: "Tus intentos",
                            count: attempts.isEmpty ? nil : attempts.count)

                if attempts.isEmpty {
                    Text("Todavía no empezaste este examen.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(attempts.enumerated()), id: \.element.id) { i, a in
                            attemptRow(a, quiz: quiz)
                            if i < attempts.count - 1 {
                                Divider().overlay(Palette.divider)
                            }
                        }
                    }
                }
            }
        }
    }

    private func attemptRow(_ a: MoodleQuizAttempt, quiz: MoodleQuiz) -> some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Intento \(a.attempt ?? 1)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let d = a.finishDate ?? a.startDate {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: Space.xs)

            if let g = a.sumgrades {
                Text(Fmt.trimNumber(g))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            Pill(text: a.stateLabel,
                 tone: a.isInProgress ? .warning : (a.isFinished ? .success : .neutral),
                 compact: true)

            if a.isInProgress {
                Button("Continuar") { open(attempt: a, quiz: quiz, review: false) }
                    .nativeGlassButton(prominent: true)
                    .tint(accent)
                    .controlSize(.small)
            } else if a.isFinished {
                Button("Revisar") { open(attempt: a, quiz: quiz, review: true) }
                    .nativeGlassButton()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func actionRow(_ quiz: MoodleQuiz) -> some View {
        VStack(spacing: Space.xs) {
            if let inProgress = attempts.first(where: \.isInProgress) {
                PrimaryButton(title: "Continuar el intento",
                              icon: "arrow.right",
                              loading: starting) {
                    open(attempt: inProgress, quiz: quiz, review: false)
                }
            } else if canStartNew {
                PrimaryButton(title: "Empezar el examen",
                              icon: "play.fill",
                              loading: starting) {
                    if quiz.requiresPassword && password.isEmpty {
                        askPassword = true
                    } else {
                        Task { await start() }
                    }
                }
            }

            openInBrowser

            Text("El examen se responde dentro de la app. Si una pregunta necesita el visor web, se avisa en el momento y se abre acá mismo.")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var canStartNew: Bool {
        let blocked = !(attemptAccess?.preventnewattemptreasons ?? []).isEmpty
        return !blocked && (access?.canattempt ?? true)
    }

    private var openInBrowser: some View {
        SecondaryButton(title: "Abrir en Moodle web", icon: "safari") {
            if let u = module.url, let url = URL(string: u) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Acciones

    private func open(attempt: MoodleQuizAttempt, quiz: MoodleQuiz, review: Bool) {
        let session = AppState.ActiveQuiz(quiz: quiz,
                                          attempt: attempt,
                                          course: course,
                                          password: password.isEmpty ? nil : password,
                                          review: review)
        dismiss()
        // El inspector es un sheet; hay que dejarlo cerrar antes de montar el
        // examinador o macOS descarta la presentación.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(Motion.spring) { state.activeQuiz = session }
        }
    }

    private func start() async {
        guard let quiz else { return }
        starting = true
        defer { starting = false }
        do {
            let attempt = try await state.moodle.startAttempt(
                quizId: quiz.id,
                password: password.isEmpty ? nil : password
            )
            open(attempt: attempt, quiz: quiz, review: false)
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await state.moodle.quizzes(courseIds: [course.id])
            // `instance` es el id del quiz; `module.id` es el del course-module.
            let match = resp.quizzes.first {
                $0.id == module.instance || $0.coursemodule == module.id
            }
            guard let found = match else {
                error = "Moodle no devolvió este cuestionario entre los del curso."
                return
            }
            quiz = found

            async let a = try? state.moodle.quizAttempts(quizId: found.id,
                                                         userId: state.moodleSiteInfo?.userid)
            async let acc = try? state.moodle.quizAccessInfo(quizId: found.id)
            async let att = try? state.moodle.attemptAccessInfo(quizId: found.id)

            attempts = (await a)?.attempts.sorted { ($0.attempt ?? 0) > ($1.attempt ?? 0) } ?? []
            access = await acc
            attemptAccess = await att

            await state.moodle.markQuizViewed(quizId: found.id)
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
        }
    }
}
