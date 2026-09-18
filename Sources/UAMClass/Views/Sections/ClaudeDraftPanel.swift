import SwiftUI
import AppKit

/// El asistente de tareas.
///
/// Claude lee el enunciado y los adjuntos del docente, resuelve la tarea y deja
/// los archivos en una carpeta tuya. **Nada se envía solo**: adjuntar lo deja en
/// BORRADOR en Moodle, y entregarlo sigue siendo un botón que apretás vos.
///
/// El registro en vivo no es decoración: ver que leyó la rúbrica antes de
/// escribir es la única forma de confiar en lo que salga.
struct ClaudeDraftPanel: View {
    let assignment: MoodleAssignment
    let course: MoodleCourse?
    /// Se llama cuando un archivo se adjuntó a Moodle, para refrescar el estado.
    var onAttached: () -> Void = {}

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @StateObject private var runner = ClaudeRunner()
    @ObservedObject private var auth = ClaudeAuth.shared

    @State private var folder: URL?
    @State private var outputs: [URL] = []
    @State private var preparing = false
    @State private var error: String?
    @State private var attaching: URL?
    @State private var attached: Set<String> = []
    @State private var expanded = true
    @ObservedObject private var store = LocalStore.shared
    @ObservedObject private var pilot = AutoPilot.shared
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var showSchedule = false
    /// Último archivo mandado a la Papelera, para poder decirlo en pantalla.
    @State private var trashed: String?

    private var installed: Bool { ClaudeRunner.isInstalled }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            headerRow

            if expanded {
                ClaudeAccountBanner()
                if runner.running || !runner.events.isEmpty {
                    activityLog
                }

                if let error { note(error, tone: Palette.danger) }
                if let f = runner.failure { note(f, tone: Palette.danger) }

                if !outputs.isEmpty {
                    resultList
                    if !outputs.contains(where: {
                        $0.lastPathComponent == "NOTAS-PARA-REVISAR.md"
                    }) {
                        note("Falta NOTAS-PARA-REVISAR.md: la corrida quedó incompleta. Revisá el entregable con cuidado o rehacela.",
                             tone: Palette.warning)
                    }
                    if let f = folder, TaskWorkspace.deliverables(in: f).isEmpty {
                        note("Ningún archivo está en formato entregable (.docx, .pdf, .xlsx…). Lo que hay son borradores de trabajo — rehacé la corrida.",
                             tone: Palette.warning)
                    }
                }

                controls
                automationRow
                disclaimer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
        .onAppear { refreshOutputs() }
    }

    // MARK: Encabezado

    private var headerRow: some View {
        Button { withAnimation(Motion.quick) { expanded.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(prefs.tint)
                Text("Resolver con Claude")
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                if runner.running {
                    ProgressView().controlSize(.small)
                } else if !outputs.isEmpty {
                    Pill(text: "\(outputs.count) archivo\(outputs.count == 1 ? "" : "s")",
                         tone: .accent, compact: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textQuaternary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Registro en vivo

    private var activityLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(runner.events) { e in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: icon(for: e.kind))
                                .font(.system(size: 9))
                                .foregroundStyle(color(for: e.kind))
                                .frame(width: 12)
                            Text(e.text)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(e.kind == .tool ? Palette.textSecondary
                                                                 : Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .id(e.id)
                    }
                }
                .padding(Space.xs)
            }
            .frame(maxHeight: 160)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.textPrimary.opacity(0.035)))
            .onChange(of: runner.events.count) { _, _ in
                if let last = runner.events.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func icon(for kind: ClaudeRunner.Event.Kind) -> String {
        switch kind {
        case .thinking: return "text.alignleft"
        case .tool:     return "wrench.and.screwdriver.fill"
        case .output:   return "checkmark.circle.fill"
        case .error:    return "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: ClaudeRunner.Event.Kind) -> Color {
        switch kind {
        case .thinking: return Palette.textQuaternary
        case .tool:     return prefs.tint
        case .output:   return Palette.success
        case .error:    return Palette.danger
        }
    }

    // MARK: Resultados

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Borrador").labelCaps()
            VStack(spacing: 0) {
                ForEach(outputs, id: \.path) { url in
                    fileRow(url)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.textPrimary.opacity(0.035)))
        }
    }

    private func fileRow(_ url: URL) -> some View {
        let isNotes = url.lastPathComponent == "NOTAS-PARA-REVISAR.md"
        return HStack(spacing: 8) {
            Image(systemName: isNotes ? "exclamationmark.bubble.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(isNotes ? Palette.warning : prefs.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if isNotes {
                    Text("Leé esto antes de entregar")
                        .font(Type.micro)
                        .foregroundStyle(Palette.warning)
                }
            }

            Spacer(minLength: 4)

            if attached.contains(url.lastPathComponent) {
                Pill(text: "En Moodle", icon: "checkmark", tone: .success, compact: true)
            }

            Button { NSWorkspace.shared.open(url) } label: {
                Image(systemName: "eye").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Abrir")

            if !isNotes {
                Button { Task { await attach(url) } } label: {
                    if attaching == url {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .help("Adjuntar a Moodle como borrador")
                .disabled(attaching != nil)
            }

            Button { trash(url) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.danger)
            }
            .buttonStyle(.plain)
            .help("Mover a la Papelera")
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, 7)
        .contextMenu {
            Button("Mostrar en Finder") { TaskWorkspace.reveal(url) }
            Divider()
            Button("Mover a la Papelera", role: .destructive) { trash(url) }
        }
    }

    /// Va a la Papelera, no a `removeItem`.
    ///
    /// Un borrado irreversible sobre el único archivo de una tarea es un mal
    /// negocio: la Papelera cuesta lo mismo y se puede deshacer. Por eso tampoco
    /// hay diálogo de confirmación — la reversibilidad ya es la red.
    private func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            SoundKit.shared.play(.back)
            trashed = url.lastPathComponent
            attached.remove(url.lastPathComponent)
            refreshOutputs()
        } catch {
            self.error = "No se pudo borrar \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: Controles

    private var controls: some View {
        HStack(spacing: Space.xs) {
            if runner.running {
                Button("Detener") { runner.cancel() }
                    .nativeGlassButton()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await start() }
                } label: {
                    Label(outputs.isEmpty ? "Resolver esta tarea" : "Rehacer",
                          systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
                .disabled(!installed || preparing || !auth.isReady)
            }

            if let f = folder {
                Button { TaskWorkspace.reveal(f) } label: {
                    Label("Carpeta", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .nativeGlassButton()
                .controlSize(.small)

                // Los scripts y los .md intermedios que Claude usa para llegar
                // al .docx no le sirven a nadie después.
                let scraps = TaskWorkspace.scraps(in: f)
                if !scraps.isEmpty {
                    Button {
                        scraps.forEach(trash)
                    } label: {
                        Label("Limpiar \(scraps.count) auxiliar\(scraps.count == 1 ? "" : "es")",
                              systemImage: "wand.and.sparkles")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                    .help("Manda a la Papelera los archivos de trabajo, no el entregable")
                }
            }

            Spacer(minLength: 0)

            if let cost = runner.costUSD {
                Text(String(format: "$%.2f", cost))
                    .font(Type.micro)
                    .foregroundStyle(Palette.textQuaternary)
                    .help("Lo que consumió esta corrida de tu suscripción")
            }
            if preparing { ProgressView().controlSize(.small) }
        }
    }

    // MARK: Piloto automático

    @ViewBuilder
    private var automationRow: some View {
        let active = store.rules(for: assignment.id).first

        VStack(alignment: .leading, spacing: 6) {
            if let active {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(active.action.isDestructive ? Palette.warning
                                                                     : prefs.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Va a \(active.summary)")
                            .font(Type.caption)
                            .foregroundStyle(Palette.textPrimary)
                        if active.action.isDestructive && active.holdOnDoubts {
                            Text("Se frena si Claude deja algo marcado como [VERIFICAR:]")
                                .font(Type.micro)
                                .foregroundStyle(Palette.textQuaternary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Cancelar") { store.removeRule(active.id) }
                        .nativeGlassButton()
                        .controlSize(.small)
                }
                .padding(Space.xs)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill((active.action.isDestructive ? Palette.warning : prefs.tint)
                        .opacity(0.10)))
            } else {
                HStack(spacing: 6) {
                    Menu {
                        Section("Apenas Claude termine") {
                            Button("Adjuntar como borrador") { add(.whenDone, .attach) }
                            Button("Entregar para calificar") { add(.whenDone, .submit) }
                        }
                        Section("A una hora") {
                            Button("Elegir hora…") { showSchedule = true }
                        }
                    } label: {
                        Label("Automatizar", systemImage: "bolt.horizontal")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .glassChip(interactive: true)

                    Spacer(minLength: 0)
                }
            }

            if let trashed {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textQuaternary)
                    Text("“\(trashed)” está en la Papelera. Si ya lo habías adjuntado, en Moodle sigue estando.")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            if let msg = pilot.lastMessage {
                Text(msg)
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popover(isPresented: $showSchedule) { schedulePopover }
    }

    private var schedulePopover: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("¿Cuándo?").labelCaps()
            DatePicker("", selection: $scheduleDate)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(width: 260)

            Text("La app tiene que estar abierta a esa hora. Si no lo está, se ejecuta apenas la abras.")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)

            HStack(spacing: Space.xs) {
                Button("Adjuntar") {
                    add(.at(scheduleDate), .attach); showSchedule = false
                }
                .nativeGlassButton()
                .controlSize(.small)
                Button("Entregar") {
                    add(.at(scheduleDate), .submit); showSchedule = false
                }
                .nativeGlassButton(prominent: true)
                .tint(Palette.warning)
                .controlSize(.small)
            }
        }
        .padding(Space.md)
    }

    private func add(_ trigger: AutomationRule.Trigger,
                     _ action: AutomationRule.Action) {
        SoundKit.shared.play(.toggle)
        store.addRule(AutomationRule(
            assignmentID: assignment.id,
            courseID: assignment.course,
            assignmentName: HTMLClean.plain(assignment.name),
            courseCode: course.map { CourseInfo(course: $0).code } ?? "",
            trigger: trigger,
            action: action))
    }

    private var disclaimer: some View {
        Text("Claude deja el trabajo como borrador. Adjuntarlo NO lo entrega: la entrega sigue siendo tuya, después de revisarlo.")
            .font(Type.micro)
            .foregroundStyle(Palette.textQuaternary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(tone)
            Text(text).font(Type.micro).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(tone.opacity(0.10)))
    }

    // MARK: Acciones

    private func start() async {
        preparing = true
        error = nil
        defer { preparing = false }
        do {
            let (dir, _) = try await TaskWorkspace.prepare(assignment: assignment,
                                                           course: course,
                                                           moodle: state.moodle)
            folder = dir
            runner.run(prompt: TaskWorkspace.prompt(assignment: assignment, course: course),
                       in: dir)
            // El registro no avisa cuándo aparece cada archivo: se relee al
            // terminar y cada tanto mientras corre.
            Task { await pollOutputs() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pollOutputs() async {
        while runner.running {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshOutputs()
        }
        refreshOutputs()
        // Recién acá se sabe que hay archivos: es el momento de que corran las
        // reglas de "al terminar".
        if runner.failure == nil, let f = folder {
            await pilot.claudeFinished(assignmentID: assignment.id, folder: f)
            attached = []
            onAttached()
        }
    }

    private func refreshOutputs() {
        let dir = folder ?? TaskWorkspace.folder(for: assignment, course: course)
        if FileManager.default.fileExists(atPath: dir.path) {
            folder = dir
            outputs = TaskWorkspace.outputs(in: dir)
        }
    }

    /// Sube TODOS los entregables juntos, no solo el que tocaste.
    ///
    /// `mod_assign_save_submission` no suma archivos: reemplaza la entrega con
    /// el área de borrador que se le pasa. Subiendo de a uno, cada adjunto
    /// borraba al anterior y quedaba solo el último — con dos archivos, la
    /// mitad del trabajo desaparecía sin aviso.
    private func attach(_ url: URL) async {
        attaching = url
        defer { attaching = nil }
        let files = folder.map { TaskWorkspace.deliverables(in: $0) } ?? []
        guard !files.isEmpty else {
            error = "No hay ningún archivo en formato entregable (.docx, .pdf, …). Claude dejó solo borradores de trabajo; rehacé la corrida."
            return
        }
        do {
            var itemId = 0
            for file in files {
                itemId = try await state.moodle.uploadDraft(fileURL: file, itemId: itemId)
            }
            try await state.moodle.saveSubmission(assignId: assignment.id,
                                                  draftItemId: itemId)
            attached = Set(files.map(\.lastPathComponent))
            SoundKit.shared.play(.confirm)
            onAttached()
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }
}
