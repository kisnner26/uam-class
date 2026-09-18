import SwiftUI

struct CourseDetailView: View {
    let course: MoodleCourse
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    enum Tab: String, CaseIterable, Identifiable {
        case contenido    = "Contenido"
        case notas        = "Notas"
        case asignaciones = "Asignaciones"
        case personas     = "Personas"
        case misNotas     = "Mis notas"
        case info         = "Info"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .contenido
    @Namespace private var tabsNS
    @State private var sections: [MoodleCourseSection] = []
    @State private var grades: [MoodleGradeItem] = []
    @State private var assignments: [MoodleAssignment] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""

    /// Filtros y vista del tab Contenido
    @State private var moduleFilter: ModuleFilter = .all
    @State private var isCompactView = false
    @State private var allExpanded = true
    @State private var contentSubview: ContentSubview = .sections

    /// Módulo actualmente inspeccionado (abre sheet).
    @State private var inspectedModule: MoodleModule?
    /// Timestamp de cuando abrimos la vista (para auto-tracking).
    @State private var viewStartTime: Date?

    enum ModuleFilter: String, CaseIterable, Identifiable {
        case all      = "Todo"
        case tareas   = "Tareas"
        case recursos = "Recursos"
        case foros    = "Foros"
        case quizzes  = "Cuestionarios"
        case urls     = "Enlaces"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all:      return "square.grid.2x2"
            case .tareas:   return "checkmark.circle"
            case .recursos: return "doc"
            case .foros:    return "bubble.left.and.bubble.right"
            case .quizzes:  return "checkmark.square"
            case .urls:     return "link"
            }
        }
        var modnames: Set<String>? {
            switch self {
            case .all:      return nil
            case .tareas:   return ["assign"]
            case .recursos: return ["resource", "folder", "page", "book"]
            case .foros:    return ["forum"]
            case .quizzes:  return ["quiz", "lesson"]
            case .urls:     return ["url"]
            }
        }
    }

    enum ContentSubview: String, CaseIterable, Identifiable {
        case sections = "Por sección"
        case timeline = "Cronología"
        var id: String { rawValue }
        var symbol: String {
            self == .sections ? "list.bullet.rectangle" : "calendar"
        }
    }

    private var info: CourseInfo { CourseInfo(course: course) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                tabsBar
                content
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1180, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task { await loadAll() }
        .onAppear {
            viewStartTime = Date()
            LocalStore.shared.trackVisit(course.id)
        }
        .onDisappear {
            if let start = viewStartTime {
                let dur = Date().timeIntervalSince(start)
                // Solo cuenta si estuvo más de 60 segundos
                if dur > 60 {
                    LocalStore.shared.logSession(courseId: course.id, start: start, duration: dur)
                }
            }
        }
        .sheet(item: $inspectedModule) { module in
            ModuleInspector(module: module, course: course)
                .environmentObject(state)
                .environmentObject(prefs)
        }
    }

    // MARK: Header

    private var header: some View {
        let accent = CourseAccent.color(for: course)
        let isFav = LocalStore.shared.isFavorite(course.id)

        return ZStack(alignment: .bottomLeading) {
            // Fondo: imagen real del UAM Virtual, o el degradé del curso con
            // el código como marca de agua.
            RemoteImage(url: course.imageURL, contentMode: .fill) {
                ZStack {
                    CourseAccent.gradient(for: course)
                    Text(info.code)
                        .font(.system(size: 120, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.10))
                        .tracking(-6)
                        .rotationEffect(.degrees(-6))
                        .offset(x: 60, y: 10)
                }
            }
            .frame(height: 208)
            .frame(maxWidth: .infinity)
            .clipped()

            // Scrim de tres paradas: el de dos siempre deja una banda sucia
            // en el medio.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.30), location: 0.0),
                    .init(color: .black.opacity(0.05), location: 0.38),
                    .init(color: .black.opacity(0.72), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Placa de información: vidrio sobre la foto. Acá el Liquid Glass
            // hace exactamente lo que debe — separar texto de una imagen que
            // no controlamos.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(info.code)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.9)))
                    if let program = info.program {
                        Text(program)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    if isFav {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.gold)
                    }
                }

                Text(info.name)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(info.meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Palette.rimOnDark, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 8)
            .padding(Space.md)

            // Acciones rápidas arriba a la derecha
            VStack {
                HStack(spacing: 6) {
                    Spacer()
                    headerAction(isFav ? "star.fill" : "star",
                                 isFav ? "Quitar de favoritos" : "Marcar favorito",
                                 filled: isFav) {
                        withAnimation(Motion.pop) { LocalStore.shared.toggleFavorite(course.id) }
                    }
                    headerAction("safari", "Abrir en el navegador") { openInBrowser() }
                }
                Spacer()
            }
            .padding(Space.sm)
        }
        .frame(height: 208)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.rimOnDark, lineWidth: 0.8)
        )
        .elevation(.mid, tint: accent)
    }

    private func headerAction(_ symbol: String, _ tooltip: String,
                              filled: Bool = false,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? Palette.gold : .white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                .symbolEffect(.bounce, value: filled)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func openInBrowser() {
        let base = state.moodleInstance.baseURL.absoluteString
        if let url = URL(string: "\(base)course/view.php?id=\(course.id)") {
            PlatformBridge.openURL(url)
        }
    }

    // MARK: Tabs

    #if os(macOS)
    private var tabsBar: some View {
        HStack(spacing: Space.sm) {
            GlassGroup(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(Tab.allCases) { t in
                        PillTab(title: t.rawValue,
                                icon: symbol(for: t),
                                selected: tab == t,
                                namespace: tabsNS) {
                            withAnimation(Motion.spring) { tab = t }
                        }
                    }
                }
                .padding(3)
                .glassBar(radius: Radius.md)
            }

            Spacer(minLength: 0)

            if tab == .contenido || tab == .asignaciones {
                SearchField(text: $search, placeholder: "Buscar en la materia", width: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            }
        }
        .animation(Motion.spring, value: tab)
    }
    #else
    // Seis pestañas + buscador no entran en una fila de iPhone (era lo que
    // colapsaba cada título letra por letra). Las pestañas van en su propio
    // riel horizontal; el buscador, debajo y solo cuando aplica.
    private var tabsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Tab.allCases) { t in
                        PillTab(title: t.rawValue,
                                icon: symbol(for: t),
                                selected: tab == t,
                                namespace: tabsNS) {
                            withAnimation(Motion.spring) { tab = t }
                        }
                    }
                }
                .padding(3)
                .glassBar(radius: Radius.md)
            }

            if tab == .contenido || tab == .asignaciones {
                SearchField(text: $search, placeholder: "Buscar en la materia", width: nil)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(Motion.spring, value: tab)
    }
    #endif

    private func symbol(for t: Tab) -> String {
        switch t {
        case .contenido:    return "square.stack.3d.up"
        case .notas:        return "chart.bar"
        case .asignaciones: return "checkmark.circle"
        case .personas:     return "person.2"
        case .misNotas:     return "note.text"
        case .info:         return "info.circle"
        }
    }

    // MARK: Content por tab

    @ViewBuilder private var content: some View {
        if loading && sections.isEmpty && grades.isEmpty && assignments.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text("Cargando…").font(Type.caption).foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, Space.md)
        } else if let err = error {
            errorBanner(err)
        } else {
            switch tab {
            case .contenido:    contenidoView
            case .notas:        notasView
            case .asignaciones: asignacionesView
            case .personas:     PeopleTab(courseId: course.id)
            case .misNotas:     MyNotesTab(course: course)
            case .info:         infoView
            }
        }
    }

    @ViewBuilder
    private var contenidoView: some View {
        contentFilterBar
        if contentSubview == .sections {
            sectionsList
        } else {
            timelineList
        }
    }

    #if os(macOS)
    private var contentFilterBar: some View {
        HStack(spacing: 8) {
            // Filtro por tipo
            HStack(spacing: 4) {
                ForEach(ModuleFilter.allCases) { f in
                    FilterChip(label: f.rawValue,
                               icon: f.symbol,
                               count: countFor(filter: f),
                               selected: moduleFilter == f) {
                        moduleFilter = f
                    }
                }
            }

            Spacer()

            // Subview switcher
            Picker("", selection: $contentSubview) {
                ForEach(ContentSubview.allCases) { v in
                    Image(systemName: v.symbol).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Cambiar vista")

            // Expand/collapse all
            if contentSubview == .sections {
                Button {
                    withAnimation(Motion.spring) { allExpanded.toggle() }
                } label: {
                    Image(systemName: allExpanded ? "chevron.up.chevron.down" : "chevron.down.chevron.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(allExpanded ? "Colapsar todo" : "Expandir todo")

                // View density
                Button {
                    isCompactView.toggle()
                } label: {
                    Image(systemName: isCompactView ? "list.bullet" : "list.bullet.rectangle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(isCompactView ? "Vista detallada" : "Vista compacta")
            }
        }
        .padding(.bottom, Space.xs)
    }
    #else
    // En iPhone no hay ancho para meter seis chips + picker + dos botones en
    // una sola fila (eso era lo que colapsaba cada Text a una letra por
    // línea). Los chips van en su propio riel horizontal; el resto, debajo.
    private var contentFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ModuleFilter.allCases) { f in
                        FilterChip(label: f.rawValue,
                                   icon: f.symbol,
                                   count: countFor(filter: f),
                                   selected: moduleFilter == f) {
                            moduleFilter = f
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Picker("", selection: $contentSubview) {
                    ForEach(ContentSubview.allCases) { v in
                        Image(systemName: v.symbol).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer(minLength: 0)

                if contentSubview == .sections {
                    Button {
                        withAnimation(Motion.spring) { allExpanded.toggle() }
                    } label: {
                        Image(systemName: allExpanded ? "chevron.up.chevron.down" : "chevron.down.chevron.up")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)

                    Button {
                        isCompactView.toggle()
                    } label: {
                        Image(systemName: isCompactView ? "list.bullet" : "list.bullet.rectangle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.bottom, Space.xs)
    }
    #endif

    private func countFor(filter: ModuleFilter) -> Int? {
        guard filter != .all else { return nil }
        let names = filter.modnames ?? []
        var total = 0
        for s in sections {
            for m in s.modules where names.contains(m.modname) {
                total += 1
            }
        }
        return total > 0 ? total : nil
    }

    private var sectionsList: some View {
        let visibleSections = sections.filter { s in
            let matchesSearch = search.isEmpty ||
                s.displayName.localizedCaseInsensitiveContains(search) ||
                s.modules.contains { $0.displayName.localizedCaseInsensitiveContains(search) }
            let matchesFilter = moduleFilter.modnames == nil ||
                s.modules.contains { moduleFilter.modnames!.contains($0.modname) }
            return matchesSearch && matchesFilter
        }
        return LazyVStack(alignment: .leading, spacing: Space.md) {
            if visibleSections.isEmpty {
                Card { EmptyState(icon: "tray", title: "Sin resultados", subtitle: nil) }
            } else {
                ForEach(visibleSections) { section in
                    SectionCard(section: section,
                                filter: search,
                                moduleFilter: moduleFilter,
                                forceExpanded: allExpanded,
                                compact: isCompactView) { m in
                        inspectedModule = m
                    }
                }
            }
        }
    }

    private var timelineList: some View {
        let filterNames = moduleFilter.modnames
        var all: [(section: String, module: MoodleModule, date: Date)] = []
        for s in sections {
            for m in s.modules {
                if let names = filterNames, !names.contains(m.modname) { continue }
                if m.modname == "label" { continue }
                if let d = m.dates?.compactMap(\.date).first {
                    all.append((s.displayName, m, d))
                }
            }
        }
        all.sort { $0.date < $1.date }
        let visible = all.filter { search.isEmpty || $0.module.displayName.localizedCaseInsensitiveContains(search) }
        return LazyVStack(alignment: .leading, spacing: 6) {
            if visible.isEmpty {
                Card {
                    EmptyState(icon: "calendar",
                               title: "Sin fechas",
                               subtitle: "Ningún módulo del curso tiene fecha asociada.")
                }
            } else {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                    TimelineRow(sectionName: item.section, module: item.module, date: item.date) {
                        inspectedModule = item.module
                    }
                }
            }
        }
    }

    private var notasView: some View {
        VStack(spacing: 0) {
            // Header de tabla
            HStack(spacing: 0) {
                Text("Ítem").labelCaps()
                Spacer()
                Text("Nota").labelCaps().frame(width: 90, alignment: .trailing)
                Text("%").labelCaps().frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)

            if grades.isEmpty {
                Card { EmptyState(icon: "chart.bar", title: "Sin ítems calificables", subtitle: nil) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(grades.enumerated()), id: \.element.id) { i, item in
                        GradeRow(item: item, isLast: i == grades.count - 1)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private var asignacionesView: some View {
        let visible = assignments.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }
        return LazyVStack(spacing: Space.sm) {
            if visible.isEmpty {
                Card { EmptyState(icon: "checkmark.circle", title: "Sin asignaciones", subtitle: nil) }
            } else {
                ForEach(visible) { a in
                    AssignmentRow(assignment: a)
                }
            }
        }
    }

    private var infoView: some View {
        VStack(spacing: Space.md) {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    InfoRow(label: "Código", value: info.code)
                    InfoRow(label: "Programa", value: info.program ?? "—")
                    InfoRow(label: "Grupo", value: info.group ?? "—")
                    InfoRow(label: "Periodo", value: [info.period, info.year].compactMap { $0 }.joined(separator: " · "))
                    InfoRow(label: "ID Moodle", value: String(course.id))
                    InfoRow(label: "Shortname", value: course.shortname)
                }
            }
            RatingCard(courseId: course.id)
            TagsEditor(courseId: course.id)
            HStack(spacing: 10) {
                SecondaryButton(title: "Compartir enlace") {
                    let deepLink = "uamclass://course/\(course.id)"
                    PlatformBridge.copyToClipboard(deepLink)
                    ToastCenter.shared.show("Enlace copiado", symbol: "link", tint: Palette.accent)
                }
                SecondaryButton(title: "Abrir en Moodle web") {
                    let base = state.moodleInstance.baseURL.absoluteString
                    if let url = URL(string: "\(base)course/view.php?id=\(course.id)") {
                        PlatformBridge.openURL(url)
                    }
                }
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Card(padding: Space.md) {
            HStack(alignment: .top, spacing: Space.xs) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Palette.danger)
                    .font(.system(size: 13, weight: .medium))
                Text(msg)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        loading = true
        defer { loading = false }
        do {
            async let secs   = state.courseContents(courseId: course.id)
            async let grades = state.courseGrades(courseId: course.id,
                                                  userId: state.moodleSiteInfo?.userid ?? 0)
            async let asns   = state.courseAssignments(courseIds: [course.id])
            let (s, g, a) = try await (secs, grades, asns)
            await MainActor.run {
                self.sections = s
                self.grades = g.usergrades.first?.gradeitems ?? []
                self.assignments = a.courses.first?.assignments ?? []
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Pill tab

/// Pestaña con indicador único que se desliza entre posiciones. El detalle que
/// convierte seis botones sueltos en un control.
private struct PillTab: View {
    let title: String
    let icon: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(selected ? Palette.textPrimary
                                      : (hovered ? Palette.textPrimary : Palette.textSecondary))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(prefs.tint.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(prefs.tint.opacity(0.30), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "courseTab", in: namespace)
                } else if hovered {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let icon: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? prefs.tint : Palette.textQuaternary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule().fill(selected ? prefs.tint.opacity(0.16)
                                                    : Palette.textPrimary.opacity(0.06))
                        )
                }
            }
            .foregroundStyle(selected ? Palette.textPrimary
                                      : (hovered ? Palette.textPrimary : Palette.textSecondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? prefs.tint.opacity(0.16)
                                        : Palette.textPrimary.opacity(hovered ? 0.06 : 0))
            )
            .overlay(
                Capsule().strokeBorder(prefs.tint.opacity(selected ? 0.28 : 0), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .animation(Motion.spring, value: selected)
    }
}

// MARK: - Section card (rediseñada: header pesado, labels inline, filtro por tipo)

private struct SectionCard: View {
    let section: MoodleCourseSection
    let filter: String
    let moduleFilter: CourseDetailView.ModuleFilter
    let forceExpanded: Bool
    let compact: Bool
    let onTap: (MoodleModule) -> Void
    @State private var expandedOverride: Bool?
    @State private var downloading = false
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var prefs: UserPrefs

    private var expanded: Bool { expandedOverride ?? forceExpanded }

    private var visibleModules: [MoodleModule] {
        section.modules.filter { m in
            let matchesFilter = moduleFilter.modnames == nil ||
                                moduleFilter.modnames!.contains(m.modname) ||
                                m.modname == "label"
            let matchesSearch = filter.isEmpty ||
                m.displayName.localizedCaseInsensitiveContains(filter) ||
                section.displayName.localizedCaseInsensitiveContains(filter)
            return matchesFilter && matchesSearch
        }
    }

    private var downloadableCount: Int {
        section.modules.reduce(0) { acc, m in
            acc + (m.contents?.filter { $0.fileurl != nil }.count ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if expanded {
                if visibleModules.isEmpty {
                    Text("Sin coincidencias con los filtros actuales")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Space.md)
                        .padding(.bottom, Space.md)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(visibleModules.enumerated()), id: \.element.id) { _, m in
                            moduleView(for: m)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !section.cleanSummary.isEmpty {
                    Text(section.cleanSummary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if downloadableCount > 0 {
                Button {
                    Task { await downloadAll() }
                } label: {
                    HStack(spacing: 4) {
                        if downloading {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle").font(.system(size: 11))
                        }
                        Text("\(downloadableCount)").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(prefs.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(prefs.tint.opacity(0.13)))
                }
                .buttonStyle(.plain)
                .help("Descargar todos los archivos de esta sección")
                .disabled(downloading)
            }

            CountBadge(section.modules.count)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.spring) { expandedOverride = !expanded }
        }
    }

    @ViewBuilder
    private func moduleView(for m: MoodleModule) -> some View {
        if m.modname == "label" {
            LabelBlock(module: m)
        } else if compact {
            CompactModuleRow(module: m) { onTap(m) }
        } else {
            RichModuleRow(module: m) { onTap(m) }
        }
    }

    private func downloadAll() async {
        downloading = true
        defer { Task { @MainActor in downloading = false } }
        let files = section.modules.flatMap { $0.contents ?? [] }.filter { $0.fileurl != nil }
        for file in files {
            guard let url = file.fileurl else { continue }
            _ = try? await state.moodle.downloadFile(fileurl: url)
        }
        await MainActor.run {
            ToastCenter.shared.show("Descargados \(files.count) archivos",
                                    symbol: "arrow.down.circle.fill",
                                    tint: Palette.success)
        }
    }
}

// MARK: - Label block (contenido inline, no clickeable)

private struct LabelBlock: View {
    let module: MoodleModule

    var body: some View {
        let text = cleanText
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Palette.border).frame(width: 2)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        } else {
            EmptyView()
        }
    }

    private var cleanText: String {
        // Preferir description (contenido real del label), sino name
        let candidate = (module.description?.isEmpty == false) ? module.description : module.name
        return HTMLClean.plain(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Rich module row (default: icon grande + info detallada)

private struct RichModuleRow: View {
    let module: MoodleModule
    let onTap: () -> Void
    @State private var hovered = false
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                IconTile(symbol: ModuleStyle.symbol(for: module.modname),
                         tint: ModuleStyle.tint(for: module.modname),
                         size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(module.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(ModuleStyle.kindLabel(for: module.modname))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ModuleStyle.tint(for: module.modname))

                        if let filesCount = fileCount, filesCount > 0 {
                            metaDot()
                            Label("\(filesCount) archivo\(filesCount == 1 ? "" : "s")",
                                  systemImage: "paperclip")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        if let totalSize = totalSize {
                            metaDot()
                            Text(totalSize)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        if let due = module.dates?.compactMap(\.date).first {
                            metaDot()
                            let overdue = due < Date()
                            Image(systemName: overdue ? "exclamationmark.circle" : "calendar")
                                .font(.system(size: 9))
                            Text(due.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(dueColor)
                }

                Spacer()

                Button {
                    withAnimation(Motion.pop) { store.toggleBookmark(module.id) }
                } label: {
                    Image(systemName: store.isBookmarked(module.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.isBookmarked(module.id)
                                         ? ModuleStyle.tint(for: module.modname)
                                         : Palette.textTertiary)
                        .frame(width: 22, height: 22)
                        .opacity(hovered || store.isBookmarked(module.id) ? 1 : 0)
                        .symbolEffect(.bounce, value: store.isBookmarked(module.id))
                }
                .buttonStyle(.plain)
                .help(store.isBookmarked(module.id) ? "Quitar marcador" : "Guardar marcador")

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovered ? Palette.textPrimary : Palette.textQuaternary)
                    .offset(x: hovered ? 2 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.textPrimary.opacity(hovered ? 0.05 : 0))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .contextMenu {
            Button {
                store.toggleBookmark(module.id)
            } label: {
                Label(store.isBookmarked(module.id) ? "Quitar marcador" : "Guardar marcador",
                      systemImage: "bookmark")
            }
            if let urlStr = module.url, let url = URL(string: urlStr) {
                Button {
                    PlatformBridge.openURL(url)
                } label: {
                    Label("Abrir en Moodle web", systemImage: "safari")
                }
            }
        }
    }

    private var fileCount: Int? {
        let n = module.contents?.filter { $0.fileurl != nil }.count ?? 0
        return n > 0 ? n : nil
    }

    private var totalSize: String? {
        let bytes = module.contents?.reduce(0) { $0 + ($1.filesize ?? 0) } ?? 0
        guard bytes > 0 else { return nil }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private var dueColor: Color {
        guard let due = module.dates?.compactMap(\.date).first else { return .secondary }
        return due < Date() ? Palette.danger : .secondary
    }

    private func metaDot() -> some View {
        Circle().fill(.quaternary).frame(width: 2, height: 2)
    }
}

// MARK: - Compact module row

private struct CompactModuleRow: View {
    let module: MoodleModule
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: ModuleStyle.symbol(for: module.modname))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ModuleStyle.tint(for: module.modname))
                    .frame(width: 18)
                Text(module.displayName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let due = module.dates?.compactMap(\.date).first {
                    Text(due.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10.5))
                        .foregroundStyle(due < Date() ? Palette.danger : Palette.textTertiary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Palette.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .consoleHover($hovered)
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let sectionName: String
    let module: MoodleModule
    let date: Date
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dateFormatter.string(from: date).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(overdueColor)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(overdueColor)
                        .monospacedDigit()
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
                .frame(width: 44)

                Rectangle().fill(Palette.divider).frame(width: 1, height: 40)

                Image(systemName: ModuleStyle.symbol(for: module.modname))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ModuleStyle.tint(for: module.modname))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(sectionName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                        Text(relativeString)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(overdueColor)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(hovered ? Palette.surfaceHover : Palette.surface)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .consoleHover($hovered)
    }

    private var overdueColor: Color {
        date < Date() ? Palette.danger : .secondary
    }
    private var relativeString: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f
    }
}

enum ModuleStyle {
    static func symbol(for modname: String) -> String {
        switch modname {
        case "assign":    return "square.and.pencil"
        case "resource":  return "doc.text"
        case "url":       return "link"
        case "forum":     return "bubble.left.and.bubble.right"
        case "quiz":      return "checkmark.square"
        case "folder":    return "folder"
        case "page":      return "doc.plaintext"
        case "book":      return "book"
        case "label":     return "text.alignleft"
        case "lesson":    return "list.bullet.rectangle"
        case "chat":      return "message"
        case "wiki":      return "text.book.closed"
        case "workshop":  return "hammer"
        case "feedback":  return "star"
        case "choice":    return "checklist"
        default:          return "circle.dashed"
        }
    }
    static func kindLabel(for modname: String) -> String {
        switch modname {
        case "assign":    return "Tarea"
        case "resource":  return "Recurso"
        case "url":       return "Enlace"
        case "forum":     return "Foro"
        case "quiz":      return "Cuestionario"
        case "folder":    return "Carpeta"
        case "page":      return "Página"
        case "book":      return "Libro"
        case "label":     return "Etiqueta"
        case "lesson":    return "Lección"
        case "chat":      return "Chat"
        case "wiki":      return "Wiki"
        case "workshop":  return "Taller"
        case "feedback":  return "Encuesta"
        case "choice":    return "Consulta"
        default:          return modname.capitalized
        }
    }
    static func tint(for modname: String) -> Color {
        switch modname {
        case "assign":    return Color(hex: 0x8C4A2A)
        case "resource":  return Color(hex: 0x3C4A5A)
        case "url":       return Color(hex: 0x2E5B62)
        case "forum":     return Color(hex: 0x5A3255)
        case "quiz":      return Color(hex: 0x2E4B3A)
        case "folder":    return Color(hex: 0x7A5A20)
        case "page":      return Color(hex: 0x3D3D50)
        case "book":      return Color(hex: 0x6E1F2A)
        case "lesson":    return Color(hex: 0x3E5A66)
        default:          return Palette.textSecondary
        }
    }
}

// MARK: - Grade row (con badge + feedback expandible)

private struct GradeRow: View {
    let item: MoodleGradeItem
    let isLast: Bool
    @State private var showFeedback = false
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = item.badge {
                        BadgePill(badge: badge)
                    }
                }
                Spacer()

                if item.hasFeedback {
                    Button {
                        withAnimation(Motion.spring) { showFeedback.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showFeedback ? "text.bubble.fill" : "text.bubble")
                                .font(.system(size: 11, weight: .medium))
                            Text(showFeedback ? "Ocultar" : "Comentario")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(showFeedback ? Palette.accent : Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(showFeedback ? Palette.accentSoft : Palette.background)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Ver comentario del docente")
                }

                Text(item.displayGrade.isEmpty ? "—" : item.displayGrade)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 80, alignment: .trailing)
                Text(item.percentageformatted ?? "—")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(hovered ? Palette.surfaceHover : Color.clear)

            if showFeedback && item.hasFeedback {
                feedbackPanel
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            if !isLast { Divider().background(Palette.divider) }
        }
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    private var feedbackPanel: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Palette.accentSoft)
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Comentario del docente")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.accent)
                Text(item.cleanFeedback)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Palette.accentSoft.opacity(0.5), Palette.accentSoft.opacity(0.15)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.accent).frame(width: 2)
        }
    }
}

struct BadgePill: View {
    let badge: HTMLClean.Badge
    var body: some View {
        let color: Color = badge.kind == .positive ? Palette.success : Palette.danger
        HStack(spacing: 4) {
            Image(systemName: badge.kind == .positive ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
            Text(badge.label).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.10))
        )
    }
}

// MARK: - Assignment row

private struct AssignmentRow: View {
    let assignment: MoodleAssignment
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Palette.background)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(HTMLClean.plain(assignment.name))
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if let due = assignment.dueDateOrNil {
                    Text("Entrega: \(due.formatted(date: .abbreviated, time: .shortened))")
                        .font(Type.caption)
                        .foregroundStyle(isOverdue(due) ? Palette.danger : Palette.textTertiary)
                }
            }
            Spacer()
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(hovered ? Palette.surfaceHover : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    private func isOverdue(_ due: Date) -> Bool { due < Date() }
}

// MARK: - Info row

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).labelCaps().frame(width: 120, alignment: .leading)
            Text(value).font(Type.body).foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
