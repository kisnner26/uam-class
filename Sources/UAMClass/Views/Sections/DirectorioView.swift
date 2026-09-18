import SwiftUI
import AppKit

/// Buscar personas de UAM Virtual por **CIF o nombre**, y abrir su ficha.
///
/// Son dos búsquedas que corren juntas:
///  · La LOCAL, instantánea, sobre el índice de participantes de tus materias
///    (ver `DirectoryIndex`).
///  · La REMOTA, que cubre a toda la universidad —cualquier persona, por CIF o
///    por nombre, compartas cursos con ella o no— combinando las vías que el
///    sitio tenga abiertas (ver `DirectoryIndex.remoteSearch`).
struct DirectorioView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @StateObject private var index = DirectoryIndex()

    @State private var query = ""
    @State private var remoteExtras: [DirectoryIndex.Entry] = []
    @State private var remoteSearching = false
    @State private var selected: DirectoryIndex.Entry?
    @State private var remoteTask: Task<Void, Never>?
    @State private var remoteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                searchField

                if index.building && index.entries.isEmpty {
                    buildingCard
                } else if let err = index.lastError, index.entries.isEmpty {
                    Card {
                        EmptyState(icon: "exclamationmark.triangle",
                                   title: "No se pudo armar el directorio",
                                   subtitle: err)
                    }
                } else if query.isEmpty {
                    browseAll
                    siteWideNote
                } else if matches.isEmpty && extras.isEmpty {
                    if remoteSearching {
                        Card {
                            EmptyState(icon: "magnifyingglass",
                                       title: "Buscando en UAM Virtual…",
                                       subtitle: "Nadie de tus materias coincide con “\(query)”. Preguntando por el resto de la universidad.")
                        }
                    } else {
                        Card {
                            EmptyState(icon: "person.slash",
                                       title: "Sin resultados",
                                       subtitle: noMatchHint)
                        }
                        if let remoteError {
                            errorNote(remoteError)
                        }
                    }
                } else {
                    resultsList
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task(id: state.courses.map(\.id)) {
            // A propósito con `courses` y no `visibleCourses`: buscar gente no
            // debería depender del filtro de período. Un compañero de un
            // semestre anterior sigue siendo alguien a quien querés encontrar.
            await index.build(courses: state.courses, moodle: state.moodle)
            // Gente de toda la universidad, ajena a tus materias. Va después
            // del índice a propósito: así no compite por las peticiones.
            await index.loadSiteWide(moodle: state.moodle,
                                     currentUserId: state.moodleSiteInfo?.userid)
        }
        .sheet(item: $selected) { entry in
            UserProfileSheet(entry: entry)
                .environmentObject(state)
                .environmentObject(prefs)
        }
    }

    // MARK: Encabezado

    private var header: some View {
        SectionHeader(
            title: "Directorio",
            eyebrow: "UAM Virtual",
            subtitle: subtitle,
            trailing: AnyView(
                HStack(spacing: 8) {
                    if index.building || remoteSearching || index.loadingSiteWide {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        Task {
                            await index.build(courses: state.courses,
                                              moodle: state.moodle, force: true)
                            await index.loadSiteWide(moodle: state.moodle,
                                                     currentUserId: state.moodleSiteInfo?.userid)
                        }
                    } label: {
                        Label("Reindexar", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                    .disabled(index.building)
                }
            )
        )
    }

    private var subtitle: String {
        if index.building {
            return "Indexando participantes… \(Int(index.progress * 100))%"
        }
        if index.entries.isEmpty { return "Buscar personas por CIF o nombre" }
        let n = index.entries.count
        var s = "\(n) persona\(n == 1 ? "" : "s") en tus materias"
        if !index.siteWide.isEmpty {
            s += " · \(index.siteWide.count) más de toda la universidad"
        }
        if !index.identityVisible { s += " · el sitio oculta los CIF" }
        return s
    }

    private var buildingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Armando el directorio con los participantes de tus materias…")
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                AccentBar(value: index.progress, tint: prefs.tint, height: 5)
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
        }
    }

    private var noMatchHint: String {
        if query.trimmingCharacters(in: .whitespaces).count < 3 {
            return "Escribí al menos 3 caracteres para buscar fuera de tus materias."
        }
        if !index.identityVisible && query.allSatisfy(\.isNumber) {
            return "Nadie coincide con “\(query)”. Este sitio de Moodle no expone los CIF de tus compañeros, y la consulta al resto de la universidad tampoco lo encontró — probá con el nombre."
        }
        return "Nadie coincide con “\(query)”, ni en tus materias ni en el resto de UAM Virtual. Revisá cómo está escrito el nombre, o probá con el CIF completo."
    }

    /// Por qué el directorio no ve más allá de tus materias, cuando no ve.
    /// Sin esto un resultado vacío parece un bug de la app y no una restricción
    /// del sitio, que es lo que casi siempre es.
    private var siteWideNote: some View {
        Group {
            if let note = index.siteWideNote, query.isEmpty {
                errorNote(note)
            }
        }
    }

    // MARK: Campo

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)

            TextField("CIF, nombre o apellido — de cualquier persona", text: $query)
                .textFieldStyle(.plain)
                .font(Type.body)
                .onChange(of: query) { _, new in scheduleRemote(new) }

            if !query.isEmpty {
                Button {
                    query = ""
                    remoteExtras = []
                    remoteError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 10)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    // MARK: Resultados

    private var matches: [DirectoryIndex.Entry] { index.search(query) }

    /// Gente que NO comparte materias con vos: la que devolvió la búsqueda
    /// remota más la que ya teníamos del padrón del sitio. De ellos Moodle
    /// entrega bastante menos, a veces solo el nombre.
    private var extras: [DirectoryIndex.Entry] {
        let mine = Set(matches.map(\.user.id))
        var seen = Set<Int>()
        return (remoteExtras + index.searchSiteWide(query)).filter { e in
            guard !mine.contains(e.user.id), seen.insert(e.user.id).inserted else { return false }
            return true
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    BlockHeader(icon: "person.2", title: "En tus materias", count: matches.count)
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { i, entry in
                            DirectoryRow(entry: entry, isLast: i == matches.count - 1) {
                                selected = entry
                            }
                        }
                    }
                    .adaptiveSurface(prefs, cornerRadius: Radius.md)
                }
            }

            if !extras.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    BlockHeader(icon: "globe", title: "En el resto de UAM Virtual", count: extras.count)
                    VStack(spacing: 0) {
                        ForEach(Array(extras.enumerated()), id: \.element.id) { i, entry in
                            DirectoryRow(entry: entry, isLast: i == extras.count - 1) {
                                selected = entry
                            }
                        }
                    }
                    .adaptiveSurface(prefs, cornerRadius: Radius.md)
                }
            }
        }
    }

    private func errorNote(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.warning)
            Text("Gente fuera de tus materias: \(msg)")
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
    }

    /// Sin búsqueda: se muestra todo agrupado, docentes primero. Un directorio
    /// que solo funciona escribiendo no deja descubrir a nadie.
    private var browseAll: some View {
        let teachers = index.entries.filter(\.isTeacherSomewhere)
        let students = index.entries.filter { !$0.isTeacherSomewhere }

        return VStack(alignment: .leading, spacing: Space.lg) {
            if !teachers.isEmpty {
                group("Docentes", icon: "person.crop.rectangle", people: teachers)
            }
            if !students.isEmpty {
                group("Compañeros", icon: "person.2", people: students)
            }
            if !index.siteWide.isEmpty {
                group("En toda la universidad", icon: "globe", people: index.siteWide)
            }
            if index.entries.isEmpty && !index.building {
                Card {
                    EmptyState(icon: "person.2",
                               title: "Directorio vacío",
                               subtitle: "No se encontraron participantes en las materias del semestre seleccionado.")
                }
            }
        }
    }

    private func group(_ title: String, icon: String,
                       people: [DirectoryIndex.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: icon, title: title, count: people.count)
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { i, entry in
                    DirectoryRow(entry: entry, isLast: i == people.count - 1) {
                        selected = entry
                    }
                }
            }
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
        }
    }

    // MARK: Búsqueda remota complementaria

    /// El índice local solo conoce a tu gente. Cualquier otra persona de UAM
    /// Virtual —por CIF, por nombre o por apellido— sale de acá.
    ///
    /// Se dispara con 3 caracteres y con un respiro de 400 ms: son hasta tres
    /// llamadas encadenadas y no tiene sentido lanzarlas por cada tecla.
    private func scheduleRemote(_ q: String) {
        remoteTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            remoteExtras = []
            remoteError = nil
            return
        }
        remoteTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            remoteSearching = true
            defer { remoteSearching = false }

            let outcome = await index.remoteSearch(
                trimmed,
                moodle: state.moodle,
                currentUserId: state.moodleSiteInfo?.userid
            )
            guard !Task.isCancelled else { return }
            remoteExtras = outcome.entries
            remoteError  = outcome.note
        }
    }
}

// MARK: - Fila

private struct DirectoryRow: View {
    let entry: DirectoryIndex.Entry
    let isLast: Bool
    let onOpen: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: Space.sm) {
                    Avatar(url: entry.user.profileimageurl ?? entry.user.profileimageurlsmall,
                           name: entry.user.fullname, size: 34,
                           userID: entry.user.id)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.properName(entry.user.fullname))
                            .font(Type.body)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let cif = entry.user.cif {
                                Text(cif)
                                    .font(Type.mono)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            if entry.remote {
                                Text("fuera de tus materias")
                                    .font(Type.micro)
                                    .foregroundStyle(Palette.textQuaternary)
                            } else {
                                Text("\(entry.courses.count) materia\(entry.courses.count == 1 ? "" : "s") en común")
                                    .font(Type.micro)
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                        }
                    }

                    Spacer(minLength: Space.xs)

                    if entry.isTeacherSomewhere {
                        Pill(text: "Docente", tone: .neutral, compact: true)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hovered ? Palette.textSecondary : Palette.textQuaternary)
                }
                .padding(.horizontal, prefs.padLarge)
                .padding(.vertical, 9)
                .background(RowHighlight(hovered: hovered, tint: Palette.accent))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .consoleHover($hovered)
            .animation(Motion.quick, value: hovered)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 58)
            }
        }
    }
}
