import SwiftUI
import AppKit

/// Qué expone la API de UAM Virtual y qué de eso la app todavía no usa.
///
/// No es una lista de nombres de función: eso no le sirve a nadie para decidir.
/// Cada fila dice **qué se podría construir**, si el sitio lo permite hoy, y qué
/// falta cuando no.
struct APIAuditSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var showUncatalogued = false

    /// Resultado de darle "Probar" a una fila. Se guarda por título de
    /// oportunidad porque las llamadas son asíncronas e independientes.
    private enum ProbeState: Equatable {
        case running
        case ok(String)
        case failed(String)
    }
    @State private var probes: [String: ProbeState] = [:]

    private var report: APIAudit.Report {
        APIAudit.run(siteInfo: state.moodleSiteInfo)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)

            if report.exposed == 0 {
                VStack {
                    Spacer()
                    EmptyState(icon: "questionmark.folder",
                               title: "Sin datos de la API",
                               subtitle: "Moodle no devolvió la lista de funciones de este token. Recargá la sesión e intentá de nuevo.")
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        summary
                        rows
                        uncatalogued
                    }
                    .padding(Space.lg)
                }
                .scrollContentBackground(.hidden)
            }

            Divider().overlay(Palette.divider)
            footer
        }
        .frame(width: 720, height: 680)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 15))
                .foregroundStyle(prefs.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Auditoría de la API")
                    .font(Type.heading)
                    .foregroundStyle(Palette.textPrimary)
                Text("Qué expone UAM Virtual y qué de eso no estamos usando")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    // MARK: Resumen

    private var summary: some View {
        let r = report
        return HStack(spacing: Space.sm) {
            metric("\(r.exposed)", "expuestas", prefs.tint)
            metric("\(r.used)", "en uso", Palette.success)
            metric("\(r.unusedCount)", "sin usar", Palette.warning)
            metric(String(format: "%.0f%%", r.coverage * 100), "cobertura", Palette.bay)
        }
    }

    private func metric(_ value: String, _ label: String, _ tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(tone)
            Text(label)
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    // MARK: Oportunidades

    private var rows: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "sparkles", title: "Qué se podría construir",
                        count: report.rows.filter(\.isBuildable).count) { EmptyView() }

            ForEach(report.rows) { row in
                opportunityCard(row)
            }
        }
    }

    private func opportunityCard(_ row: APIAudit.Row) -> some View {
        let tone: Color = row.isComplete ? Palette.success
                        : (row.isBuildable ? Palette.warning : Palette.textQuaternary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: row.isComplete ? "checkmark.circle.fill"
                                 : (row.isBuildable ? "circle.lefthalf.filled" : "xmark.circle"))
                    .font(.system(size: 12))
                    .foregroundStyle(tone)

                Text(row.opportunity.title)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)

                if row.opportunity.impact == 3 {
                    Pill(text: "alto impacto", tone: .accent, compact: true)
                }
                Spacer(minLength: 0)
                Text(row.isComplete ? "disponible"
                     : (row.isBuildable ? "\(row.available.count)/\(row.opportunity.functions.count)"
                                        : "no expuesta"))
                    .font(Type.micro)
                    .foregroundStyle(tone)
            }

            Text(row.opportunity.detail)
                .font(Type.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !row.missing.isEmpty {
                Text("Falta: " + row.missing.joined(separator: ", "))
                    .font(Type.mono)
                    .foregroundStyle(Palette.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if row.isBuildable {
                probeRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
        .opacity(row.isBuildable ? 1 : 0.6)
    }

    // MARK: Probar en vivo

    @ViewBuilder
    private func probeRow(_ row: APIAudit.Row) -> some View {
        let key = row.opportunity.title
        HStack(alignment: .top, spacing: 7) {
            switch probes[key] {
            case .none:
                Button {
                    runProbe(row)
                } label: {
                    Label("Probar", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(prefs.tint)

            case .running:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Llamando a Moodle…")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }

            case .ok(let summary):
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .font(.system(size: 11))
                    Text(summary)
                        .font(Type.mono)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    retryButton(row)
                }

            case .failed(let message):
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.danger)
                        .font(.system(size: 11))
                    Text(message)
                        .font(Type.mono)
                        .foregroundStyle(Palette.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    retryButton(row)
                }
            }
        }
        .padding(.top, 2)
    }

    private func retryButton(_ row: APIAudit.Row) -> some View {
        Button {
            runProbe(row)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textQuaternary)
    }

    /// Llama de verdad a una función representativa de la fila y guarda el
    /// resultado. Solo prueba funciones de LECTURA: nada que marque algo como
    /// visto, cree un evento o publique un post — eso tiene efectos reales en
    /// Moodle y no se dispara sin que el usuario lo pida explícitamente desde
    /// la función real, no desde este botón de diagnóstico.
    private func runProbe(_ row: APIAudit.Row) {
        let key = row.opportunity.title
        probes[key] = .running
        let moodle = state.moodle
        let userId = state.moodleSiteInfo?.userid
        let courseId = state.courses.first?.id
        let courseIds = state.courses.map(\.id)

        Task {
            do {
                let summary = try await probeSummary(for: key, moodle: moodle,
                                                      userId: userId,
                                                      courseId: courseId,
                                                      courseIds: courseIds)
                await MainActor.run {
                    probes[key] = .ok(summary)
                    SoundKit.shared.play(.confirm)
                }
            } catch {
                await MainActor.run {
                    probes[key] = .failed((error as? MoodleClient.APIError)?.message
                                           ?? error.localizedDescription)
                }
            }
        }
    }

    private func probeSummary(for title: String, moodle: MoodleClient,
                              userId: Int?, courseId: Int?,
                              courseIds: [Int]) async throws -> String {
        func need<T>(_ v: T?, _ what: String) throws -> T {
            guard let v else {
                throw MoodleClient.APIError(message: "Necesito \(what) — abrí la app normal primero.",
                                             errorcode: nil)
            }
            return v
        }

        switch title {
        case "Agenda unificada":
            let events = try await moodle.actionEventsByTimesort(limitNum: 5)
            return "\(events.count) evento(s) próximo(s)."

        case "Notificaciones reales de Moodle":
            let uid = try need(userId, "tu userid")
            let resp = try await moodle.popupNotifications(userId: uid, limit: 5)
            let unread = try await moodle.unreadConversationsCount(userId: uid)
            return "\(resp.notifications.count) notificación(es), \(unread) conversación(es) sin leer."

        case "Progreso real por actividad":
            let uid = try need(userId, "tu userid")
            let cid = try need(courseId, "al menos una materia cargada")
            let statuses = try await moodle.activitiesCompletionStatus(courseId: cid, userId: uid)
            return "\(statuses.count) actividad(es) con estado de finalización."

        case "Búsqueda global del sitio":
            let resp = try await moodle.searchSite(query: "a")
            return "\(resp.results.count) resultado(s) para una búsqueda de prueba."

        case "Notas del docente sobre vos":
            let uid = try need(userId, "tu userid")
            let notes = try await moodle.courseNotes(userId: uid)
            let total = (notes?.personal?.count ?? 0) + (notes?.course?.count ?? 0) + (notes?.site?.count ?? 0)
            return "\(total) nota(s) de docente encontradas."

        case "Notas de todas las materias de una":
            let uid = try need(userId, "tu userid")
            let grades = try await moodle.overviewGrades(userId: uid)
            return "\(grades.count) materia(s) con nota consolidada."

        case "Lecciones":
            let ids = courseIds.isEmpty ? try need(courseId.map { [$0] }, "al menos una materia cargada") : courseIds
            let lessons = try await moodle.lessons(courseIds: ids)
            return "\(lessons.count) lección(es) en tus materias."

        case "Talleres y evaluación entre pares":
            let ids = courseIds.isEmpty ? try need(courseId.map { [$0] }, "al menos una materia cargada") : courseIds
            let workshops = try await moodle.workshops(courseIds: ids)
            return "\(workshops.count) taller(es) en tus materias."

        case "Glosarios":
            let ids = courseIds.isEmpty ? try need(courseId.map { [$0] }, "al menos una materia cargada") : courseIds
            let glossaries = try await moodle.glossaries(courseIds: ids)
            return "\(glossaries.count) glosario(s) en tus materias."

        case "Tus archivos privados":
            let uid = try need(userId, "tu userid")
            let info = try await moodle.privateFilesInfo(userId: uid)
            return "\(info.filecount ?? 0) archivo(s), \(info.foldercount ?? 0) carpeta(s)."

        case "Grupos del curso":
            let uid = try need(userId, "tu userid")
            let cid = try need(courseId, "al menos una materia cargada")
            let groups = try await moodle.courseUserGroups(courseId: cid, userId: uid)
            return "\(groups.count) grupo(s) en esa materia."

        case "Módulos sin visor":
            let ids = courseIds.isEmpty ? try need(courseId.map { [$0] }, "al menos una materia cargada") : courseIds
            async let dbs = moodle.databases(courseIds: ids)
            async let wks = moodle.wikis(courseIds: ids)
            async let bks = moodle.books(courseIds: ids)
            async let scs = moodle.scorms(courseIds: ids)
            let (d, w, b, s) = try await (dbs, wks, bks, scs)
            return "\(d.count) base(s) de datos, \(w.count) wiki(s), \(b.count) libro(s), \(s.count) SCORM."

        case "Eventos propios en Moodle", "Marcar como visto", "Foros completos":
            return "Esta oportunidad solo tiene funciones de escritura (crean, marcan o publican algo real) — no se prueban automáticamente desde acá."

        default:
            return "Sin prueba automática configurada todavía."
        }
    }

    // MARK: Lo no catalogado

    @ViewBuilder
    private var uncatalogued: some View {
        let extras = report.uncatalogued
        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Button {
                    withAnimation(Motion.quick) { showUncatalogued.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showUncatalogued ? 90 : 0))
                        Text("Otras \(extras.count) funciones sin usar")
                            .font(Type.bodyBold)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showUncatalogued {
                    Text("Expuestas por el sitio y no catalogadas arriba. Acá aparece lo que no anticipé — vale la pena mirarlo.")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)

                    Text(extras.joined(separator: "\n"))
                        .font(Type.mono)
                        .foregroundStyle(Palette.textTertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.sm)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.textPrimary.opacity(0.04)))
                }
            }
        }
    }

    // MARK: Pie

    private var footer: some View {
        HStack(spacing: Space.xs) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plainReport(), forType: .string)
                SoundKit.shared.play(.confirm)
            } label: {
                Label("Copiar informe", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .nativeGlassButton()
            .controlSize(.small)

            Spacer()
            Button("Cerrar") { dismiss() }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    /// Texto plano para pegarlo donde sea — incluso acá, en el chat.
    private func plainReport() -> String {
        let r = report
        var out = "AUDITORÍA DE LA API — UAM Virtual\n"
        out += "\(r.exposed) funciones expuestas · \(r.used) en uso · \(r.unusedCount) sin usar\n\n"
        for row in r.rows {
            let mark = row.isComplete ? "[✓]" : (row.isBuildable ? "[~]" : "[ ]")
            out += "\(mark) \(row.opportunity.title)\n"
            if !row.available.isEmpty {
                out += "    disponibles: \(row.available.joined(separator: ", "))\n"
            }
            if !row.missing.isEmpty {
                out += "    faltan: \(row.missing.joined(separator: ", "))\n"
            }
        }
        if !r.uncatalogued.isEmpty {
            out += "\nSIN CATALOGAR (\(r.uncatalogued.count)):\n"
            out += r.uncatalogued.joined(separator: "\n")
        }
        return out
    }
}
