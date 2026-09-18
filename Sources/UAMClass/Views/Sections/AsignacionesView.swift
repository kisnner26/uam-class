import SwiftUI

struct AsignacionesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var groups: [MoodleAssignmentCourse] = []
    @State private var loading = false
    @State private var error: String?
    @State private var scope: Scope = .pendientes
    @State private var selected: MoodleAssignment?

    enum Scope: String, CaseIterable, Identifiable, Hashable {
        case pendientes, vencidas, todas
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pendientes: return "Pendientes"
            case .vencidas:   return "Vencidas"
            case .todas:      return "Todas"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if loading && groups.isEmpty {
                    loadingCard
                } else if visibleGroups.isEmpty {
                    Card {
                        EmptyState(icon: scope == .pendientes ? "checkmark.circle" : "tray",
                                   title: emptyTitle,
                                   subtitle: error ?? emptySubtitle)
                    }
                } else {
                    VStack(spacing: Space.md) {
                        ForEach(visibleGroups, id: \.id) { group in
                            groupCard(group)
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
        .sheet(item: $selected) { a in
            AssignmentSheet(assignment: a,
                            course: state.courses.first { $0.id == a.course })
                .environmentObject(state)
                .environmentObject(prefs)
        }
    }

    // MARK: Header

    private var header: some View {
        SectionHeader(
            title: "Tareas",
            eyebrow: "Entregas",
            subtitle: "\(countAll) asignaciones · \(countPending) pendientes",
            trailing: AnyView(
                GlassSegmented(selection: $scope,
                               options: Scope.allCases.map { .init($0, label: $0.label) })
            )
        )
    }

    private var loadingCard: some View {
        Card {
            VStack(spacing: Space.sm) {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
        }
    }

    // MARK: Grupos

    private func groupCard(_ group: MoodleAssignmentCourse) -> some View {
        let course = state.courses.first { $0.id == group.id }
        let accent = course.map(CourseAccent.color(for:)) ?? prefs.tint
        let code = course.map { CourseInfo(course: $0).code } ?? group.shortname
        let items = filtered(group.assignments)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(code)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Text(HTMLClean.plain(group.fullname))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                CountBadge(items.count)
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, Space.sm)

            Divider().overlay(Palette.divider)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                    AssignmentLine(assignment: a, accent: accent) { selected = a }
                    if i < items.count - 1 {
                        Divider().overlay(Palette.divider).padding(.leading, prefs.padLarge)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    // MARK: Data

    private var countAll: Int { groups.flatMap(\.assignments).count }
    private var countPending: Int {
        groups.flatMap(\.assignments).filter { ($0.dueDateOrNil ?? .distantPast) > Date() }.count
    }

    private func filtered(_ items: [MoodleAssignment]) -> [MoodleAssignment] {
        let now = Date()
        let out: [MoodleAssignment]
        switch scope {
        case .pendientes: out = items.filter { ($0.dueDateOrNil ?? .distantFuture) > now }
        case .vencidas:   out = items.filter { ($0.dueDateOrNil ?? .distantFuture) <= now }
        case .todas:      out = items
        }
        return out.sorted { ($0.dueDateOrNil ?? .distantFuture) < ($1.dueDateOrNil ?? .distantFuture) }
    }

    private var visibleGroups: [MoodleAssignmentCourse] {
        groups.filter { !filtered($0.assignments).isEmpty }
    }

    private var emptyTitle: String {
        switch scope {
        case .pendientes: return "Nada pendiente"
        case .vencidas:   return "Sin tareas vencidas"
        case .todas:      return "Sin tareas visibles"
        }
    }

    private var emptySubtitle: String {
        switch scope {
        case .pendientes: return "No tenés entregas con fecha futura. Disfrutá."
        case .vencidas:   return "Ninguna entrega pasó su fecha límite."
        case .todas:      return "Moodle no devolvió asignaciones para estos cursos."
        }
    }

    private func load() async {
        guard !state.visibleCourses.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let resp = try await state.moodle.assignments(courseIds: state.visibleCourses.map(\.id))
            await MainActor.run {
                withAnimation(Motion.fade) { self.groups = resp.courses }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Línea de asignación

private struct AssignmentLine: View {
    let assignment: MoodleAssignment
    let accent: Color
    let onOpen: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    private var due: Date? { assignment.dueDateOrNil }
    private var overdue: Bool { (due ?? .distantFuture) <= Date() }
    private var urgent: Bool {
        guard let d = due else { return false }
        return !overdue && d.timeIntervalSinceNow < 86_400 * 2
    }

    var body: some View {
        Button(action: onOpen) { row }
            .buttonStyle(.plain)
    }

    private var row: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(overdue ? Palette.danger : accent.opacity(0.6))
                .frame(width: 16)

            Text(HTMLClean.plain(assignment.name))
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            if let d = due {
                HStack(spacing: 6) {
                    Text(d.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(Type.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)

                    Pill(text: relative(d),
                         icon: overdue ? "xmark" : (urgent ? "flame.fill" : nil),
                         tone: overdue ? .danger : (urgent ? .warning : .neutral),
                         compact: true)
                }
            } else {
                Text("Sin fecha")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textQuaternary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovered ? Palette.textSecondary : Palette.textQuaternary.opacity(0.5))
        }
        .padding(.horizontal, prefs.padLarge)
        .padding(.vertical, 9)
        .background(RowHighlight(hovered: hovered, tint: Palette.accent))
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
