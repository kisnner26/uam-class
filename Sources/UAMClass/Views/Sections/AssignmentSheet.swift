import SwiftUI
import UniformTypeIdentifiers

/// La tarea completa: enunciado, estado de tu entrega y la forma de subirla.
///
/// Subir a Moodle son tres pasos y la pantalla los respeta en vez de esconderlos,
/// porque la diferencia importa: un archivo adjunto sigue siendo un BORRADOR
/// hasta que lo enviás para calificar. Más de una tarea se perdió por creer que
/// con adjuntar alcanzaba.
struct AssignmentSheet: View {
    let assignment: MoodleAssignment
    let course: MoodleCourse?

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var status: MoodleAssignSubmissionStatus?
    @State private var loading = true
    @State private var busy: String?
    @State private var error: String?
    @State private var justUploaded: String?
    @State private var showFileImporter = false

    private var attempt: MoodleAssignLastAttempt? { status?.lastattempt }
    private var submission: MoodleAssignSubmission? { attempt?.submission }
    private var due: Date? { assignment.dueDateOrNil }
    private var overdue: Bool { (due ?? .distantFuture) <= Date() }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Palette.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    dueCard
                    if loading {
                        Card { SkeletonRow() }
                    } else {
                        statusCard
                        #if os(macOS)
                        ClaudeDraftPanel(assignment: assignment, course: course) {
                            Task { await load() }
                        }
                        #endif
                        filesCard
                        actionsCard
                    }
                    if let intro = cleanIntro, !intro.isEmpty {
                        introCard(intro)
                    }
                    if let error { errorNote(error) }
                }
                .padding(Space.lg)
            }
            .scrollContentBackground(.hidden)
        }
        #if os(macOS)
        .frame(width: 620, height: 660)
        #endif
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
        .task { await load() }
    }

    // MARK: Encabezado

    private var headerBar: some View {
        HStack(spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(course.map { CourseAccent.color(for: $0) } ?? prefs.tint)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                if let c = course {
                    Text(CourseInfo(course: c).code)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textTertiary)
                }
                Text(HTMLClean.plain(assignment.name))
                    .font(Type.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.sm)

            if let cmid = assignment.cmid {
                Button {
                    openInBrowser(cmid: cmid)
                } label: {
                    Label("Abrir en Moodle", systemImage: "safari")
                        .font(.system(size: 11))
                }
                .nativeGlassButton()
                .controlSize(.small)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    // MARK: Fecha

    private var dueCard: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "calendar")
                .font(.system(size: 13))
                .foregroundStyle(overdue ? Palette.danger : prefs.tint)

            if let d = due {
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide)
                                        .hour().minute()))
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                    Text(overdue ? "La fecha ya pasó" : "Entrega \(relative(d))")
                        .font(Type.micro)
                        .foregroundStyle(overdue ? Palette.danger : Palette.textTertiary)
                }
            } else {
                Text("Sin fecha de entrega")
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    // MARK: Estado

    private var statusCard: some View {
        let s = submission
        let label: String
        let symbol: String
        let color: Color
        if s?.isSubmitted == true {
            label = "Enviada para calificar"
            symbol = "checkmark.seal.fill"; color = Palette.success
        } else if s?.isDraft == true {
            // El caso peligroso: el archivo está, pero el docente no lo ve.
            label = "Borrador — todavía NO enviada"
            symbol = "exclamationmark.triangle.fill"; color = Palette.warning
        } else {
            label = "Sin entregar"
            symbol = "circle"; color = Palette.textTertiary
        }

        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(label)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }

            if let g = attempt?.feedback?.gradefordisplay, !HTMLClean.plain(g).isEmpty {
                Text("Calificación: \(HTMLClean.plain(g))")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            if attempt?.submissionsenabled == false {
                Text("El docente cerró las entregas para esta tarea.")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    // MARK: Archivos ya entregados

    @ViewBuilder
    private var filesCard: some View {
        let files = submission?.files ?? []
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                BlockHeader(icon: "paperclip", title: "Archivos entregados",
                            count: files.count) { EmptyView() }
                VStack(spacing: 0) {
                    ForEach(files) { f in
                        HStack(spacing: Space.xs) {
                            Image(systemName: "doc")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textTertiary)
                            Text(f.displayName)
                                .font(Type.caption)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let s = f.sizeText {
                                Text(s)
                                    .font(Type.micro)
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                        }
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 7)
                    }
                }
                .adaptiveSurface(prefs, cornerRadius: Radius.md)
            }
        }
    }

    // MARK: Acciones

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let justUploaded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .font(.system(size: 11))
                    Text("“\(justUploaded)” quedó adjunto como borrador.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            HStack(spacing: Space.xs) {
                Button {
                    showFileImporter = true
                } label: {
                    Label(busy == nil ? "Elegir archivo…" : busy!,
                          systemImage: "arrow.up.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .nativeGlassButton()
                .controlSize(.regular)
                .disabled(busy != nil || attempt?.submissionsenabled == false)
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                    if case .success(let url) = result {
                        Task { await upload(fileURL: url) }
                    }
                }

                Button {
                    Task { await submit() }
                } label: {
                    Label("Enviar para calificar", systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.regular)
                .disabled(busy != nil || submission?.isSubmitted == true
                          || (submission?.files.isEmpty ?? true) && justUploaded == nil)

                if busy != nil { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }

            Text("Adjuntar deja la tarea en borrador. Recién “Enviar para calificar” se la muestra al docente — y según cómo la haya configurado, puede que después no se pueda editar.")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    private func introCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "text.alignleft", title: "Enunciado") { EmptyView() }
            Text(text)
                .font(Type.body)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveSurface(prefs, cornerRadius: Radius.md)
        }
    }

    private func errorNote(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.danger)
            Text(msg)
                .font(Type.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.danger.opacity(0.10)))
    }

    // MARK: Datos

    private var cleanIntro: String? {
        let t = HTMLClean.plain(assignment.intro)
        return t.isEmpty ? nil : t
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            status = try await state.moodle.submissionStatus(assignId: assignment.id)
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func upload(fileURL url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        error = nil
        busy = "Subiendo…"
        defer { busy = nil }

        do {
            let itemId = try await state.moodle.uploadDraft(fileURL: url)
            busy = "Adjuntando…"
            try await state.moodle.saveSubmission(assignId: assignment.id,
                                                  draftItemId: itemId)
            justUploaded = url.lastPathComponent
            await load()
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func submit() async {
        error = nil
        busy = "Enviando…"
        defer { busy = nil }
        do {
            try await state.moodle.submitForGrading(assignId: assignment.id)
            justUploaded = nil
            await load()
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func openInBrowser(cmid: Int) {
        // Vía `MoodleOpener`: abre la página con la sesión ya iniciada en vez
        // de dejarte en el login del sitio.
        MoodleOpener.shared.open(path: "mod/assign/view.php?id=\(cmid)", state: state)
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}
