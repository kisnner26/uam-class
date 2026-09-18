import SwiftUI
import AppKit

/// Búsqueda global ⌘K. Panel de vidrio flotando sobre un velo desenfocado,
/// con navegación por teclado real (↑ ↓ ↵ esc).
struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var fileSearch = LocalFileSearch.shared
    @State private var query = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            paletteCard
                .padding(.top, 88)
                .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
        }
        .onAppear { focused = true }
        .onExitCommand { close() }
    }

    private var backdrop: some View {
        Rectangle()
            .fill(Palette.scrim)
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
            .onTapGesture { close() }
    }

    // MARK: Card

    private var paletteCard: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(Palette.divider)
            resultsList
            Divider().overlay(Palette.divider)
            footerHints
        }
        .frame(width: 660, height: 486)
        .glassPanel(radius: Radius.xxl, elevation: .floating)
        .shadow(color: .black.opacity(0.35), radius: 60, x: 0, y: 30)
        // Las flechas se capturan en la card entera para que sigan andando
        // aunque el foco esté en el campo de texto.
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
    }

    private var searchBar: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(prefs.tint)

            TextField("Buscar materias, archivos, acciones…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
                .onSubmit { activate(results[safe: selectedIndex]) }
                .onChange(of: query) { _, _ in selectedIndex = 0 }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }

            KeyCap(key: "esc")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.md)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                    if results.isEmpty {
                        emptyView
                    } else {
                        ForEach(Array(groupedResults), id: \.0) { group, items in
                            Section {
                                ForEach(items, id: \.element.id) { entry in
                                    Button {
                                        activate(entry.element)
                                    } label: {
                                        ResultRow(result: entry.element,
                                                  selected: selectedIndex == entry.offset,
                                                  tint: prefs.tint)
                                    }
                                    .buttonStyle(.plain)
                                    .id(entry.offset)
                                    .onHover { if $0 { selectedIndex = entry.offset } }
                                }
                            } header: {
                                Text(group)
                                    .labelCaps()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Space.md)
                                    .padding(.top, Space.sm)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .padding(.bottom, Space.xs)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: selectedIndex) { _, new in
                withAnimation(Motion.quick) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: query.isEmpty ? "command" : "text.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.textQuaternary)
            Text(query.isEmpty ? "Empezá a escribir" : "Sin resultados para “\(query)”")
                .font(Type.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    private var footerHints: some View {
        HStack(spacing: Space.sm) {
            hint("↑↓", "navegar")
            hint("↵", "abrir")
            hint("esc", "cerrar")
            Spacer()
            Text("\(results.count) resultado\(results.count == 1 ? "" : "s")")
                .font(Type.micro)
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 9)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(key: key)
            Text(label)
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Navegación

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(results.count - 1, next))
    }

    // MARK: - Search

    var results: [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [SearchResult] = []

        for c in state.courses {
            let info = CourseInfo(course: c)
            if q.isEmpty
                || info.name.lowercased().contains(q)
                || info.code.lowercased().contains(q)
                || c.shortname.lowercased().contains(q) {
                out.append(.course(c))
            }
        }

        if !q.isEmpty {
            for f in fileSearch.search(q).prefix(20) {
                out.append(.file(f))
            }
        }

        for action in Self.actions where action.matches(q) {
            out.append(.action(id: action.id, title: action.title,
                               subtitle: action.subtitle, symbol: action.symbol))
        }

        return out
    }

    /// Resultados agrupados conservando el índice global, para que las flechas
    /// recorran la lista entera sin importar en qué grupo estén.
    private var groupedResults: [(String, [(offset: Int, element: SearchResult)])] {
        let indexed = Array(results.enumerated()).map { (offset: $0.offset, element: $0.element) }
        var groups: [(String, [(offset: Int, element: SearchResult)])] = []

        func bucket(_ name: String, _ filter: (SearchResult) -> Bool) {
            let items = indexed.filter { filter($0.element) }
            if !items.isEmpty { groups.append((name, items)) }
        }

        bucket("Materias") { if case .course = $0 { return true }; return false }
        bucket("Archivos") { if case .file = $0 { return true }; return false }
        bucket("Acciones") { if case .action = $0 { return true }; return false }
        return groups
    }

    private struct QuickAction {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let keywords: [String]

        func matches(_ q: String) -> Bool {
            q.isEmpty || keywords.contains { $0.contains(q) } || title.lowercased().contains(q)
        }
    }

    private static let actions: [QuickAction] = [
        .init(id: "archive", title: "Archivar semestre",
              subtitle: "Descargar todos los materiales del semestre actual",
              symbol: "archivebox",
              keywords: ["archivar", "descargar", "semestre", "backup"]),
        .init(id: "timer", title: "Iniciar sesión de estudio",
              subtitle: "Timer Pomodoro con registro de tiempo",
              symbol: "timer",
              keywords: ["timer", "estudiar", "pomodoro", "sesión"]),
        .init(id: "ical", title: "Exportar entregas al Calendario",
              subtitle: "Genera un .ics con las próximas fechas",
              symbol: "calendar.badge.plus",
              keywords: ["calendario", "ical", "ics", "exportar"]),
        .init(id: "reindex", title: "Re-indexar materiales locales",
              subtitle: "Escanea ~/Downloads/UAM Class para búsqueda",
              symbol: "sparkle.magnifyingglass",
              keywords: ["indexar", "reindex", "buscar", "archivos"]),
        .init(id: "picker", title: "Cambiar plataforma",
              subtitle: "Volver al selector",
              symbol: "rectangle.on.rectangle",
              keywords: ["cambiar", "plataforma", "moodle", "class"]),
        .init(id: "refresh", title: "Recargar datos",
              subtitle: "Volver a pedir cursos y notas a Moodle",
              symbol: "arrow.clockwise",
              keywords: ["recargar", "actualizar", "refresh", "sync"])
    ]

    private func activate(_ r: SearchResult?) {
        guard let r = r else { return }
        close()
        switch r {
        case .course(let c):
            state.pendingCourseOpen = c
        case .file(let f):
            NSWorkspace.shared.open(f.url)
        case .action(let id, _, _, _):
            switch id {
            case "archive": state.showArchiver = true
            case "picker":  state.backToPicker()
            case "refresh": Task { await state.refreshCourses() }
            case "timer":   state.showStudyTimer = true
            case "ical":
                var byId: [Int: MoodleCourse] = [:]
                for c in state.courses { byId[c.id] = c }
                ICalExporter.exportAndOpen(assignments: state.upcomingAssignments,
                                            coursesById: byId)
            case "reindex":
                Task { await fileSearch.rebuildIndex() }
            default: break
            }
        }
    }

    private func close() {
        withAnimation(Motion.spring) { state.showCommandPalette = false }
    }
}

// MARK: - Result models

enum SearchResult: Identifiable {
    case course(MoodleCourse)
    case action(id: String, title: String, subtitle: String, symbol: String)
    case file(LocalFileSearch.FileEntry)

    var id: String {
        switch self {
        case .course(let c): return "course-\(c.id)"
        case .action(let id, _, _, _): return "action-\(id)"
        case .file(let f): return "file-\(f.url.absoluteString)"
        }
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: Space.sm) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                if case .file(let f) = result, let ex = f.excerpt, !ex.isEmpty, selected {
                    Text(ex)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: Space.xs)

            if selected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 7)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(tint.opacity(0.26), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, Space.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch result {
        case .course(let c):
            IconTile(text: String(CourseInfo(course: c).code.prefix(3)),
                     tint: CourseAccent.color(for: c), size: 30)
        case .action(_, _, _, let symbol):
            IconTile(symbol: symbol, tint: tint, size: 30)
        case .file(let f):
            IconTile(symbol: Self.fileSymbol(f.filename), tint: Palette.textSecondary, size: 30)
        }
    }

    private static func fileSymbol(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                        return "doc.richtext"
        case "png", "jpg", "jpeg", "heic": return "photo"
        case "mp4", "mov", "m4v":          return "film"
        case "zip", "rar":                 return "doc.zipper"
        case "md", "txt":                  return "doc.plaintext"
        case "pptx", "ppt":                return "rectangle.on.rectangle"
        case "xlsx", "xls", "csv":         return "tablecells"
        case "docx", "doc":                return "doc.text"
        default:                           return "doc"
        }
    }

    private var title: String {
        switch result {
        case .course(let c):          return CourseInfo(course: c).name
        case .action(_, let t, _, _): return t
        case .file(let f):            return f.filename
        }
    }

    private var subtitle: String {
        switch result {
        case .course(let c):
            let info = CourseInfo(course: c)
            var parts: [String] = [info.code]
            if let g = info.group { parts.append("Grupo \(g)") }
            if let p = info.period, let y = info.year { parts.append("\(p)C · \(y)") }
            return parts.joined(separator: " · ")
        case .action(_, _, let s, _):
            return s
        case .file(let f):
            return "\(f.course) · \(f.period)"
        }
    }
}

// Utility
private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
