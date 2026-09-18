import SwiftUI

struct MateriasView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @State private var search = ""
    @State private var mode: Mode = .grid
    @State private var sort: Sort = .name

    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case grid, list
        var id: String { rawValue }
        var label: String { self == .grid ? "Cuadrícula" : "Lista" }
        var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
    }

    enum Sort: String, CaseIterable, Identifiable, Hashable {
        case name, code, rating
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name:   return "Nombre"
            case .code:   return "Código"
            case .rating: return "Dificultad"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                #if !os(macOS)
                toolbarRow
                #endif
                if !favoriteCourses.isEmpty && search.isEmpty {
                    favoritesSection
                }
                allCoursesSection
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Header

    private var header: some View {
        #if os(macOS)
        SectionHeader(
            title: "Materias",
            eyebrow: "Semestre actual",
            subtitle: "\(state.visibleCourses.count) matriculadas · \(favoriteCourses.count) favoritas",
            trailing: AnyView(
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        SearchField(text: $search, placeholder: "Buscar materia", width: 170)
                        sortMenu
                        GlassSegmented(selection: $mode,
                                       options: Mode.allCases.map {
                                           .init($0, label: $0.label, symbol: $0.symbol)
                                       },
                                       iconsOnly: true)
                    }
                }
            )
        )
        #else
        SectionHeader(
            title: "Materias",
            eyebrow: "Semestre actual",
            subtitle: "\(state.visibleCourses.count) matriculadas · \(favoriteCourses.count) favoritas"
        )
        #endif
    }

    #if !os(macOS)
    /// Buscador, orden y grilla/lista: en Mac viven a la derecha del título;
    /// en iPhone no hay ancho para eso (170 + menú + segmentado no entraba
    /// junto al título), así que van en su propia fila.
    private var toolbarRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $search, placeholder: "Buscar materia", width: 150)
            sortMenu
            Spacer(minLength: 0)
            GlassSegmented(selection: $mode,
                           options: Mode.allCases.map {
                               .init($0, label: $0.label, symbol: $0.symbol)
                           },
                           iconsOnly: true)
        }
    }
    #endif

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar por", selection: $sort) {
                ForEach(Sort.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(sort.label)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassChip(interactive: true)
        .help("Ordenar materias")
    }

    // MARK: Favoritos

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            BlockHeader(icon: "star.fill", title: "Favoritos", count: favoriteCourses.count)
            gridOrList(courses: sorted(favoriteCourses))
        }
    }

    // MARK: Todas

    private var allCoursesSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            BlockHeader(icon: "square.grid.2x2.fill",
                        title: search.isEmpty ? "Todas" : "Resultados",
                        count: filtered.count)

            if filtered.isEmpty {
                Card {
                    EmptyState(icon: "magnifyingglass",
                               title: search.isEmpty ? "Sin materias" : "Sin coincidencias",
                               subtitle: search.isEmpty
                                   ? "No hay materias matriculadas en este semestre."
                                   : "Nada coincide con “\(search)”. Probá con el código o parte del nombre.",
                               actionTitle: search.isEmpty ? nil : "Limpiar búsqueda") {
                        search = ""
                    }
                }
            } else {
                gridOrList(courses: sorted(filtered))
            }
        }
    }

    @ViewBuilder
    private func gridOrList(courses: [MoodleCourse]) -> some View {
        if mode == .grid {
            // Mosaicos, no tarjetas: mismo tamaño, misma lámina de color, todos
            // pulsables. Es la vista de canales de la consola.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240),
                                   spacing: Space.sm, alignment: .top)],
                alignment: .leading,
                spacing: Space.sm
            ) {
                ForEach(courses) { c in
                    courseTile(c)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { i, c in
                    NavigationLink(value: c) {
                        MateriaRow(course: c, isLast: i == courses.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .adaptiveSurface(prefs, cornerRadius: Radius.lg)
        }
    }

    private func courseTile(_ course: MoodleCourse) -> some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)

        return ChannelTile(title: info.name,
                           subtitle: info.group.map { "Grupo \($0)" } ?? info.program,
                           eyebrow: info.code,
                           accent: accent,
                           aspect: 1.25) {
            ZStack {
                GlyphArt(text: String(info.name.prefix(1)).uppercased())
                if store.isFavorite(course.id) {
                    VStack {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 2)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                if let p = course.progress, p > 0 {
                    ArtFooter(text: "\(Int(p))%")
                }
            }
        } action: {
            state.pendingCourseOpen = course
        }
        .contextMenu {
            Button(store.isFavorite(course.id) ? "Quitar de favoritos" : "Marcar favorita") {
                store.toggleFavorite(course.id)
            }
        }
    }

    // MARK: Data

    private var favoriteCourses: [MoodleCourse] {
        state.visibleCourses.filter { store.isFavorite($0.id) }
    }

    private var filtered: [MoodleCourse] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return state.visibleCourses }
        return state.visibleCourses.filter { c in
            let info = CourseInfo(course: c)
            return info.name.lowercased().contains(q)
                || info.code.lowercased().contains(q)
                || c.shortname.lowercased().contains(q)
        }
    }

    private func sorted(_ courses: [MoodleCourse]) -> [MoodleCourse] {
        switch sort {
        case .name:
            return courses.sorted { CourseInfo(course: $0).name < CourseInfo(course: $1).name }
        case .code:
            return courses.sorted { CourseInfo(course: $0).code < CourseInfo(course: $1).code }
        case .rating:
            return courses.sorted { store.rating(for: $0.id) > store.rating(for: $1.id) }
        }
    }
}

// MARK: - Fila

struct MateriaRow: View {
    let course: MoodleCourse
    let isLast: Bool
    @State private var hovered = false
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)

        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 34)

                IconTile(text: String(info.code.prefix(3)), tint: accent, size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(info.code)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(accent)
                        if store.isFavorite(course.id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Palette.gold)
                        }
                        if let g = info.group {
                            Text("· G\(g)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Palette.textQuaternary)
                        }
                    }
                    Text(info.name)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.sm)

                Text(info.meta)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovered ? accent : Palette.textQuaternary)
                    .offset(x: hovered ? 2 : 0)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 9)
            .background(Palette.textPrimary.opacity(hovered ? 0.045 : 0))

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 72)
            }
        }
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
