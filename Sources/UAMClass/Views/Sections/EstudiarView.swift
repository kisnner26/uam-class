import SwiftUI
import AppKit

/// Estudiar con el material de tu propia materia.
///
/// La respuesta sale de los PDFs que subió tu docente, no del conocimiento
/// general del modelo — y viene con la cita del archivo de donde salió. Esa es
/// toda la diferencia con preguntarle a un chatbot: acá se puede verificar.
struct EstudiarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @StateObject private var runner = ClaudeRunner()
    @ObservedObject private var auth = ClaudeAuth.shared

    @State private var course: MoodleCourse?
    @State private var mode: StudyWorkspace.Mode = .ask
    @State private var question = ""
    @State private var preparing = false
    @State private var materials = 0
    @State private var answer: String?
    @State private var error: String?
    @State private var indexed = false
    @State private var hasMap = false
    @State private var indexNote: String?
    @State private var buildingMap = false

    private var installed: Bool { ClaudeRunner.isInstalled }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                header
                ClaudeAccountBanner()
                courseRail
                if course != nil {
                    indexPanel
                    modeRail
                    askBox
                    if runner.running || !runner.events.isEmpty { activity }
                    if let error { warn(error) }
                    if let answer { answerCard(answer) }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if course == nil { course = state.visibleCourses.first }
            refresh()
        }
    }

    // MARK: Encabezado

    private var header: some View {
        SectionHeader(
            title: "Estudiar",
            eyebrow: "Con tu material",
            subtitle: subtitle,
            trailing: AnyView(
                HStack(spacing: 8) {
                    if preparing || runner.running { ProgressView().controlSize(.small) }
                    if let c = course {
                        Button { TaskWorkspace.reveal(StudyWorkspace.folder(for: c)) } label: {
                            Label("Carpeta", systemImage: "folder")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .nativeGlassButton()
                        .controlSize(.small)
                    }
                }
            )
        )
    }

    private var subtitle: String {
        guard course != nil else { return "Elegí una materia" }
        if preparing { return "Descargando el material del docente…" }
        if materials == 0 {
            return "Sin material descargado todavía — se baja al preguntar"
        }
        return "\(materials) archivo\(materials == 1 ? "" : "s") del docente en tu Mac"
    }

    // MARK: Materias

    private var courseRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(state.visibleCourses) { c in
                    let on = c.id == course?.id
                    let info = CourseInfo(course: c)
                    Button {
                        SoundKit.shared.play(.select)
                        course = c
                        answer = nil
                        refresh()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.code)
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(on ? Palette.textOnAccent
                                                    : CourseAccent.color(for: c))
                            Text(info.name)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(on ? Palette.textOnAccent
                                                    : Palette.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(on ? CourseAccent.color(for: c) : Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Índice y mapa
    //
    // La barra que explica por qué las consultas son rápidas: el texto ya está
    // extraído y el mapa ya está escrito.

    @ViewBuilder
    private var indexPanel: some View {
        if let c = course {
            HStack(spacing: Space.sm) {
                Image(systemName: indexed ? (hasMap ? "brain.filled.head.profile"
                                                    : "doc.text.magnifyingglass")
                                          : "tray.and.arrow.down")
                    .font(.system(size: 13))
                    .foregroundStyle(indexed && hasMap ? Palette.success : prefs.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(indexState)
                        .font(Type.caption)
                        .foregroundStyle(Palette.textPrimary)
                    if let indexNote {
                        Text(indexNote)
                            .font(Type.micro)
                            .foregroundStyle(Palette.textQuaternary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if buildingMap { ProgressView().controlSize(.small) }

                if indexed && !hasMap && !buildingMap {
                    Button { buildMap(c) } label: {
                        Label("Construir mapa", systemImage: "brain")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .nativeGlassButton(prominent: true)
                    .tint(prefs.tint)
                    .controlSize(.small)
                    .help("Una corrida de ~1 minuto que hace más baratas y rápidas todas las consultas siguientes")
                } else if indexed {
                    Button { rebuild(c) } label: {
                        Label("Reindexar", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                    .disabled(buildingMap)
                }
            }
            .padding(Space.sm)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill((indexed && hasMap ? Palette.success : prefs.tint).opacity(0.08)))
        }
    }

    private var indexState: String {
        if !indexed { return "Sin indexar — se arma solo en la primera consulta" }
        // El mapa es lo que de verdad abarata las consultas. Medido: sin él,
        // cada pregunta cuesta ~$0.70; con él, ~$0.43. Se paga en dos preguntas.
        if !hasMap { return "Texto indexado · sin mapa, cada consulta explora de cero" }
        return "Indexada y mapeada — las consultas arrancan sabiendo dónde buscar"
    }

    // MARK: Modo

    private var modeRail: some View {
        HStack(spacing: 6) {
            ForEach(StudyWorkspace.Mode.allCases) { m in
                let on = m == mode
                Button {
                    SoundKit.shared.play(.toggle)
                    mode = m
                    answer = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.symbol).font(.system(size: 10))
                        Text(m.label).font(Type.caption)
                    }
                    .foregroundStyle(on ? Palette.textOnAccent : Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(on ? prefs.tint
                                                  : Palette.textPrimary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Pregunta

    private var askBox: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                TextField(mode.placeholder, text: $question)
                    .textFieldStyle(.plain)
                    .font(Type.body)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
                    .onSubmit { start() }

                if runner.running {
                    Button("Detener") { runner.cancel() }
                        .nativeGlassButton()
                        .controlSize(.regular)
                } else {
                    Button {
                        start()
                    } label: {
                        Label(mode == .ask ? "Preguntar" : "Generar",
                              systemImage: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .nativeGlassButton(prominent: true)
                    .tint(prefs.tint)
                    .controlSize(.regular)
                    .disabled(!installed || preparing || !auth.isReady
                              || (mode.needsQuestion && question.trimmingCharacters(
                                    in: .whitespaces).isEmpty))
                }
            }

            Text(hint)
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    private var hint: String {
        mode == .practice
            ? "Las respuestas van al final, después de una línea divisoria, para poder resolverlo sin espiar."
            : "Cada afirmación viene con el archivo del docente de donde salió. Si algo no está en el material, te lo dice."
    }

    // MARK: Actividad y respuesta

    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(runner.events.suffix(6)) { e in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: e.kind == .tool ? "magnifyingglass" : "text.alignleft")
                        .font(.system(size: 9))
                        .foregroundStyle(e.kind == .tool ? prefs.tint : Palette.textQuaternary)
                        .frame(width: 12)
                    Text(e.text)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.textPrimary.opacity(0.035)))
    }

    private func answerCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: 7) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(prefs.tint)
                Text(mode.label)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                if let c = course {
                    Button {
                        NSWorkspace.shared.open(StudyWorkspace.output(mode: mode, course: c))
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Abrir el archivo")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    SoundKit.shared.play(.confirm)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Copiar")
            }

            Divider().overlay(Palette.divider)
            MarkdownView(text: text)
        }
        .padding(Space.md)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private func warn(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Palette.warning)
            Text(msg).font(Type.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.warning.opacity(0.10)))
    }

    // MARK: Acciones

    private func refresh() {
        guard let c = course else { return }
        materials = StudyWorkspace.materialCount(for: c)
        indexed = CourseIndex.exists(for: c)
        hasMap = CourseIndex.hasMap(for: c)
        indexNote = nil
    }

    /// El mapa: una corrida cara que abarata todas las siguientes.
    private func buildMap(_ c: MoodleCourse) {
        buildingMap = true
        error = nil
        Task {
            runner.run(prompt: StudyWorkspace.mapPrompt(course: c),
                       in: StudyWorkspace.folder(for: c))
            while runner.running {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            buildingMap = false
            hasMap = CourseIndex.hasMap(for: c)
            if !hasMap {
                error = runner.failure ?? "Claude no dejó MAPA.md. Probá de nuevo."
            } else {
                SoundKit.shared.play(.confirm)
            }
        }
    }

    private func rebuild(_ c: MoodleCourse) {
        Task {
            preparing = true
            defer { preparing = false }
            _ = try? await StudyWorkspace.prepare(course: c, moodle: state.moodle)
            if let summary = try? CourseIndex.build(for: c) {
                indexed = !summary.isEmpty
                indexNote = "\(summary.entries.count) archivo\(summary.entries.count == 1 ? "" : "s") reindexado\(summary.entries.count == 1 ? "" : "s")"
            }
            materials = StudyWorkspace.materialCount(for: c)
        }
    }

    private func start() {
        guard let c = course else { return }
        answer = nil
        error = nil
        Task {
            preparing = true
            do {
                let result = try await StudyWorkspace.prepare(course: c, moodle: state.moodle)
                materials = result.downloaded
                preparing = false

                guard result.downloaded > 0 else {
                    error = "No hay material descargable en esta materia. El docente puede no haber subido archivos, o ser todos enlaces y videos."
                    return
                }

                // Extracción de texto: gratis, instantánea y sin red. Es lo que
                // evita que cada consulta vuelva a abrir los PDFs.
                if let summary = try? CourseIndex.build(for: c) {
                    indexed = !summary.isEmpty
                    indexNote = summary.failed.isEmpty
                        ? "\(summary.entries.count) archivo\(summary.entries.count == 1 ? "" : "s") · \(summary.totalCharacters.formatted()) caracteres de texto"
                        : "\(summary.failed.count) archivo\(summary.failed.count == 1 ? "" : "s") sin texto extraíble (escaneos sin OCR)"
                }
                hasMap = CourseIndex.hasMap(for: c)

                runner.run(prompt: StudyWorkspace.prompt(mode: mode, question: question,
                                                         course: c),
                           in: StudyWorkspace.folder(for: c))
                await waitAndLoad(course: c)
            } catch {
                preparing = false
                self.error = error.localizedDescription
            }
        }
    }

    private func waitAndLoad(course c: MoodleCourse) async {
        while runner.running {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        if let f = runner.failure { error = f; return }
        let out = StudyWorkspace.output(mode: mode, course: c)
        if let text = try? String(contentsOf: out, encoding: .utf8), !text.isEmpty {
            answer = text
            SoundKit.shared.play(.confirm)
        } else {
            error = "Claude terminó pero no dejó \(mode.outputName). Probá de nuevo."
        }
    }
}
