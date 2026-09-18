import SwiftUI

struct NotasView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var loading = false
    @State private var byCourse: [Int: [MoodleGradeItem]] = [:]
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if !byCourse.isEmpty {
                    summaryRow
                }

                if state.visibleCourses.isEmpty {
                    Card {
                        EmptyState(icon: "chart.bar.doc.horizontal",
                                   title: "Sin cursos cargados",
                                   subtitle: "Cargá materias desde Inicio primero.")
                    }
                } else {
                    VStack(spacing: Space.md) {
                        ForEach(state.visibleCourses) { c in
                            CourseGradesCard(course: c,
                                             items: byCourse[c.id] ?? [],
                                             loading: loading && byCourse[c.id] == nil)
                        }
                    }
                }

                if let err = error {
                    errorCard(err)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task(id: state.visibleCourses.map(\.id)) { await loadAll() }
    }

    private var header: some View {
        SectionHeader(title: "Calificaciones",
                      eyebrow: "Semestre actual",
                      subtitle: "Notas y comentarios del docente, por materia",
                      trailing: loading ? AnyView(
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Cargando").font(Type.micro)
                                .foregroundStyle(Palette.textTertiary)
                        }
                      ) : nil)
    }

    // MARK: Resumen

    /// Un vistazo agregado arriba de todo: cuántas notas hay, cuántas
    /// aprobadas y el promedio ponderado por porcentaje.
    private var summaryRow: some View {
        let all = byCourse.values.flatMap { $0 }
        let graded = all.filter { $0.graderaw != nil }
        let passed = all.filter { $0.badge?.kind == .positive }.count
        let failed = all.filter { $0.badge?.kind == .negative }.count

        let pcts: [Double] = graded.compactMap { item in
            guard let raw = item.graderaw, let max = item.grademax, max > 0 else { return nil }
            return raw / max * 100
        }
        let avg = pcts.isEmpty ? nil : pcts.reduce(0, +) / Double(pcts.count)

        let tiles = Group {
            MetricTile(icon: "number", label: "Ítems calificados",
                       value: "\(graded.count)", tint: prefs.tint)
            MetricTile(icon: "percent", label: "Promedio",
                       value: avg.map { String(format: "%.1f", $0) } ?? "—",
                       tint: Palette.bay)
            MetricTile(icon: "checkmark.seal.fill", label: "Aprobadas",
                       value: "\(passed)", tint: Palette.success)
            MetricTile(icon: "xmark.seal.fill", label: "Reprobadas",
                       value: "\(failed)", tint: failed > 0 ? Palette.danger : Palette.textSecondary)
        }
        #if os(macOS)
        return HStack(spacing: prefs.gap) { tiles }
        #else
        // Cuatro tiles en una sola fila no entran en el ancho de un iPhone
        // (cada uno se aplastaba hasta envolver el texto letra por letra).
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: prefs.gap),
                                   GridItem(.flexible(), spacing: prefs.gap)],
                         spacing: prefs.gap) { tiles }
        #endif
    }

    private func errorCard(_ err: String) -> some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Error al cargar notas")
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(err)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.danger.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.danger.opacity(0.22), lineWidth: 0.5)
        )
    }

    private func loadAll() async {
        guard let uid = state.moodleSiteInfo?.userid else { return }
        loading = true
        defer { loading = false }
        for course in state.visibleCourses {
            do {
                let resp = try await state.moodle.gradeItems(courseId: course.id, userId: uid)
                let items = resp.usergrades.first?.gradeitems ?? []
                await MainActor.run {
                    withAnimation(Motion.fade) { byCourse[course.id] = items }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Card por curso

struct CourseGradesCard: View {
    @EnvironmentObject private var prefs: UserPrefs
    let course: MoodleCourse
    let items: [MoodleGradeItem]
    let loading: Bool

    @State private var collapsed = false

    private var accent: Color { CourseAccent.color(for: course) }

    /// Cómo va la materia en la escala de la UAM (300 puntos, 210 para pasar).
    private var standing: CourseStanding? { CourseStanding(items: items) }

    var body: some View {
        let info = CourseInfo(course: course)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spring) { collapsed.toggle() }
            } label: {
                HStack(spacing: Space.sm) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(width: 3, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.code)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(accent)
                        Text(info.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Space.sm)

                    if loading {
                        ProgressView().controlSize(.small)
                    } else if let st = standing {
                        // Lo que de verdad importa de un vistazo: cuántos de los
                        // 300 puntos del semestre lleva, y si eso alcanza.
                        Text("\(Int(st.earnedPoints.rounded())) / 300")
                            .font(Type.mono)
                            .foregroundStyle(Palette.textSecondary)
                        Pill(text: st.standing.label,
                             icon: st.standing.symbol,
                             tone: .custom(st.standing.tone),
                             compact: true)
                    } else if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.textPrimary.opacity(0.07)))
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textQuaternary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, Space.sm)

            if !collapsed {
                Divider().overlay(Palette.divider)

                if items.isEmpty && !loading {
                    Text("Sin ítems calificables.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, prefs.padLarge)
                        .padding(.vertical, Space.sm)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            NotasRowMini(item: item, accent: accent)
                            if i < items.count - 1 {
                                Divider().overlay(Palette.divider)
                                    .padding(.leading, prefs.padLarge)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }

                if let st = standing { standingFooter(st) }

                // La proyección hacia adelante, al lado del acumulado.
                GradeScenarioCard(courseCode: info.code, courseName: info.name)
                    .padding(.horizontal, prefs.padLarge)
                    .padding(.bottom, Space.sm)
            }
        }
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    /// La lectura en castellano de los números de arriba. Sin esto hay que
    /// acordarse de memoria de dónde caen los umbrales.
    private func standingFooter(_ st: CourseStanding) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: st.standing.symbol)
                .font(.system(size: 10))
                .foregroundStyle(st.standing.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(footerText(st))
                    .font(Type.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if st.isPartial {
                    Text("Calculado sobre lo que hay calificado hasta ahora, no sobre el semestre completo.")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, prefs.padLarge)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.sm)
    }

    private func footerText(_ st: CourseStanding) -> String {
        let pct = String(format: "%.1f", st.percent)
        switch st.standing {
        case .aprobada:
            return "\(pct) promediado · pasa el umbral de 70 (210 de 300 puntos)."
        case .convocatoria:
            let falta = st.pointsToPass.map { " Faltan \(Int($0.rounded())) puntos para los 210." } ?? ""
            return "\(pct) promediado · derecho a examen de convocatoria.\(falta)"
        case .reprobada:
            let falta = st.pointsToPass.map { " Faltan \(Int($0.rounded())) puntos para los 210." } ?? ""
            return "\(pct) promediado · bajo 60, sin derecho a convocatoria.\(falta)"
        }
    }
}

// MARK: - Fila de nota

struct NotasRowMini: View {
    let item: MoodleGradeItem
    var accent: Color = Palette.accent

    @EnvironmentObject private var prefs: UserPrefs
    @State private var showFeedback = false
    @State private var hovered = false

    /// 0…1 cuando Moodle da nota cruda y máximo. Es lo que permite dibujar
    /// la barra en vez de mostrar solo un número suelto.
    private var ratio: Double? {
        guard let raw = item.graderaw, let max = item.grademax, max > 0 else { return nil }
        return Swift.min(1, raw / max)
    }

    private var barColor: Color {
        guard let r = ratio else { return Palette.textQuaternary }
        if r >= 0.8 { return Palette.success }
        if r >= 0.6 { return Palette.gold }
        return Palette.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let badge = item.badge {
                            BadgePill(badge: badge)
                        }
                        if let r = ratio {
                            AccentBar(value: r, tint: barColor, height: 4)
                                .frame(width: 90)
                        }
                    }
                }

                Spacer(minLength: Space.xs)

                if item.hasFeedback {
                    Button {
                        withAnimation(Motion.spring) { showFeedback.toggle() }
                    } label: {
                        Image(systemName: showFeedback ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(showFeedback ? accent : Palette.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(accent.opacity(showFeedback ? 0.14 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Comentario del docente")
                }

                Text(item.displayGrade.isEmpty ? "—" : item.displayGrade)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.displayGrade.isEmpty ? Palette.textTertiary
                                                               : Palette.textPrimary)
                    .frame(width: 62, alignment: .trailing)

                Text(item.percentageformatted.map { HTMLClean.plain($0) } ?? "—")
                    .font(Type.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, 8)
            .background(RowHighlight(hovered: hovered, tint: Palette.accent))
            .consoleHover($hovered)

            if showFeedback && item.hasFeedback {
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(accent)
                        .frame(width: 2.5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Comentario del docente")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(accent)
                        Text(item.cleanFeedback)
                            .font(Type.caption)
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(2.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(accent.opacity(0.07))
                )
                .padding(.horizontal, prefs.padLarge)
                .padding(.bottom, Space.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.quick, value: hovered)
    }
}
