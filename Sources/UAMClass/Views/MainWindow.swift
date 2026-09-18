import SwiftUI

// `AppSection` vive en Models/AppSection.swift — AppState (compartido con iOS)
// la referencia directamente.

// MARK: - Main Window

struct MainWindow: View {
    let platform: Platform
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var selection: AppSection?
    @State private var navPath = NavigationPath()
    @State private var showArchiver = false
    @State private var showTimer = false
    @State private var showSettings = false
    @State private var showAudit = false

    var body: some View {
        NavigationSplitView {
            Sidebar(platform: platform, selection: $selection)
                .navigationSplitViewColumnWidth(min: 216, ideal: 264, max: 380)
        } detail: {
            NavigationStack(path: $navPath) {
                sectionRoot
                    .id(selection)
                    // Cruce puro. Antes esto además se desplazaba 6 pt, y como
                    // la vista saliente sigue montada durante la animación, se
                    // veían las dos encimadas y corridas.
                    .transition(.opacity)
                    .animation(Motion.fade, value: selection)
                    .navigationTitle(currentSection.title)
                    .navigationSubtitle(platform.displayName)
                    .toolbar { toolbarContent }
                    .navigationDestination(for: MoodleCourse.self) { course in
                        CourseDetailView(course: course)
                    }
            }
            // El ambiente vive acá y se extiende por debajo del sidebar y de la
            // toolbar: es lo que esos paneles de vidrio terminan refractando.
            .background {
                AmbientBackdrop(tint: prefs.tint, intensity: 0.62)
                    .sidebarBackgroundExtension()
            }
            .softScrollEdges()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selection == nil {
                selection = AppSection.forPlatform(platform).first
            }
            // El piloto automático de tareas necesita un reloj corriendo.
            AutoPilot.shared.start(state: state)
            ClaudeAuth.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Volver a la ventana es el momento natural en que la sesión pudo
            // cambiar: acabás de loguearte en Terminal, o pasó un día.
            ClaudeAuth.shared.refresh()
        }
        .sheet(isPresented: $showAudit) {
            APIAuditSheet()
                .environmentObject(state)
                .environmentObject(prefs)
        }
        .onChange(of: state.pendingSectionOpen) { _, section in
            guard let section else { return }
            withAnimation(Motion.spring) { selection = section }
            navPath = NavigationPath()
            state.pendingSectionOpen = nil
        }
        .onChange(of: state.pendingCourseOpen) { _, course in
            guard let course = course else { return }
            state.pendingCourseOpen = nil
            // Una sola asignación a `navPath`. Vaciarla y volver a llenarla en
            // el mismo ciclo dejaba a NavigationStack con dos transiciones
            // pisándose: la vista vieja no terminaba de salir cuando la nueva
            // ya estaba entrando, y quedaban las dos dibujadas.
            var fresh = NavigationPath()
            fresh.append(course)
            if selection != .materias {
                selection = .materias
                // Un respiro para que la sección termine de cambiar antes de
                // empujar el detalle encima.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    navPath = fresh
                }
            } else {
                navPath = fresh
            }
        }
        .onChange(of: state.showStudyTimer) { _, show in
            if show { showTimer = true; state.showStudyTimer = false }
        }
        .onChange(of: state.showArchiver) { _, show in
            if show { showArchiver = true; state.showArchiver = false }
        }
        .sheet(isPresented: $showArchiver) {
            ArchiverSheet(moodle: state.moodle)
                .environmentObject(state).environmentObject(prefs)
        }
        .sheet(isPresented: $showTimer) {
            StudyTimerSheet()
                .environmentObject(state).environmentObject(prefs)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(state).environmentObject(prefs)
        }
    }

    private var currentSection: AppSection {
        selection ?? AppSection.forPlatform(platform).first!
    }

    @ViewBuilder private var sectionRoot: some View {
        switch currentSection {
        case .dashboard:    DashboardView()
        case .materias:     MateriasView()
        case .notasMoodle:  NotasView()
        case .asignaciones: AsignacionesView()
        case .examenes:     ExamenesView()
        case .asistencia:   AsistenciaView()
        case .bookmarks:    BookmarksView()
        case .mensajes:     MensajesView()
        case .directorio:   DirectorioView()
        case .estadisticas: EstadisticasView()
        case .personales:   PersonalesView()
        case .horario:      HorarioView()
        case .estudiar:     EstudiarView()
        case .novedades:    NovedadesView()
        case .logros:       LogrosView()
        case .notasClass:   NotasAcademicasView()
        case .aranceles:    ArancelesView()
        }
    }

    // MARK: - Toolbar
    //
    // Tres acciones visibles y un menú para el resto.
    //
    // Antes había siete iconos apretados en una sola píldora, más un botón de
    // sidebar DUPLICADO: `NavigationSplitView` ya inserta el suyo en macOS 26,
    // así que el nuestro lo repetía. El criterio ahora es de frecuencia de uso:
    // lo que se toca todos los días queda a la vista; archivar el semestre se
    // hace una vez cada seis meses y no merece un icono permanente.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if state.isOffline {
            ToolbarItem(placement: .status) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 10, weight: .medium))
                    Text("Sin conexión")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.warning)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .overlay(Capsule().strokeBorder(Palette.warning.opacity(0.35), lineWidth: 1))
                .help("Sin conexión a Moodle. Datos desde cache local.")
            }
        }

        // El semestre: alcance de toda la ventana. Va con la navegación, no
        // con las acciones — dice DÓNDE estás parado, no qué podés hacer.
        if platform == .moodle && !state.availablePeriods.isEmpty {
            ToolbarItem(placement: .navigation) {
                PeriodPicker()
            }
        }

        // Empuja todo lo que sigue al extremo opuesto. Sin esto, los cinco
        // controles quedaban amontonados contra la barra lateral.
        ToolbarSpacer(.flexible, placement: .primaryAction)

        // Buscar: la acción principal, sola y separada del resto.
        if platform == .moodle && !state.courses.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button { state.showCommandPalette = true } label: {
                    Label("Buscar", systemImage: "magnifyingglass")
                }
                .help("Buscar todo (⌘K)")
                .keyboardShortcut("k", modifiers: [.command])
            }
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        // Lo cotidiano.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await state.refreshCourses() }
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .help("Recargar")

            if platform == .moodle && !state.courses.isEmpty {
                Button { showTimer = true } label: {
                    Label("Sesión de estudio", systemImage: "timer")
                }
                .help("Sesión de estudio (⌘T)")
            }
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        // Todo lo ocasional, plegado.
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if platform == .moodle && !state.courses.isEmpty {
                    Button {
                        var byId: [Int: MoodleCourse] = [:]
                        for c in state.courses { byId[c.id] = c }
                        ICalExporter.exportAndOpen(assignments: state.upcomingAssignments,
                                                    coursesById: byId)
                    } label: {
                        Label("Añadir entregas al Calendario", systemImage: "calendar.badge.plus")
                    }

                    Button { showArchiver = true } label: {
                        Label("Archivar semestre…", systemImage: "archivebox")
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                    Divider()
                }

                if platform == .moodle {
                    Button { showAudit = true } label: {
                        Label("Auditoría de la API…", systemImage: "chart.bar.doc.horizontal")
                    }
                }

                Button { showSettings = true } label: {
                    Label("Configuración…", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button { state.backToPicker() } label: {
                    Label("Cambiar plataforma", systemImage: "rectangle.on.rectangle")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            } label: {
                Label("Más acciones", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .help("Más acciones")
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    let platform: Platform
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @Binding var selection: AppSection?

    @Namespace private var navNS

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            navList
            Spacer(minLength: 0)
            footer
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Cursos pinneados

    private var pinnedCourses: [MoodleCourse] {
        guard platform == .moodle else { return [] }
        let favs = store.favoriteCourseIds
        return state.visibleCourses.filter { favs.contains($0.id) }
    }

    // MARK: Brand

    private var brandHeader: some View {
        HStack(spacing: Space.sm) {
            BrandMark()
            VStack(alignment: .leading, spacing: 0) {
                Text(platform.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(platform.subtitle)
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
        .padding(.bottom, Space.sm)
    }

    // MARK: Profile

    @ViewBuilder private var profileCard: some View {
        if state.moodleSiteInfo != nil, platform == .moodle {
            // Solo la cuenta. El semestre se mudó a la barra de herramientas:
            // acá abajo quedaba escondido y su menú se abría hacia arriba,
            // tapando media barra lateral.
            AccountSwitcher()
            .padding(.horizontal, Space.sm)
            .padding(.bottom, Space.sm)
        } else {
            EmptyView()
        }
    }

    // MARK: Nav

    private var navList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.md) {
                sectionGroup("Principal", sections: primarySections)
                if !secondarySections.isEmpty {
                    sectionGroup("Herramientas", sections: secondarySections)
                }
                if !pinnedCourses.isEmpty {
                    pinnedGroup
                }
            }
            .padding(.top, 4)
            .padding(.bottom, Space.sm)
        }
        .scrollContentBackground(.hidden)
    }

    private var pinnedGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel("Favoritos")
            VStack(spacing: 1) {
                ForEach(pinnedCourses) { c in
                    PinnedCourseRow(course: c)
                        .onTapGesture { state.pendingCourseOpen = c }
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }

    private var primarySections: [AppSection] {
        switch platform {
        case .moodle:      return [.dashboard, .materias, .notasMoodle, .asignaciones, .examenes, .asistencia, .horario, .estudiar]
        case .classPortal: return [.personales, .horario, .notasClass, .aranceles]
        }
    }
    private var secondarySections: [AppSection] {
        switch platform {
        case .moodle:      return [.novedades, .logros, .bookmarks, .mensajes, .directorio, .estadisticas]
        case .classPortal: return []
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Palette.textQuaternary)
            .textCase(.uppercase)
            .tracking(0.9)
            .padding(.horizontal, Space.md)
            .padding(.bottom, 5)
    }

    private func sectionGroup(_ title: String, sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel(title)
            VStack(spacing: 1) {
                ForEach(sections) { s in
                    SidebarRow(section: s,
                               selected: selection == s,
                               badge: badge(for: s),
                               namespace: navNS)
                        .onTapGesture {
                            SoundKit.shared.play(.select)
                            withAnimation(Motion.spring) { selection = s }
                        }
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }

    /// Contadores en vivo. Un número al lado del ítem ahorra un click.
    private func badge(for section: AppSection) -> Int? {
        switch section {
        case .materias:     return state.visibleCourses.isEmpty ? nil : state.visibleCourses.count
        case .asignaciones: return state.upcomingAssignments.isEmpty ? nil
                                 : state.upcomingAssignments.count
        case .bookmarks:
            let n = store.bookmarkedIds.count
            return n == 0 ? nil : n
        case .novedades:
            let n = ChangeWatcher.shared.unseenCount
            return n == 0 ? nil : n
        default:            return nil
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 2) {
            Divider().overlay(Palette.divider).padding(.bottom, 6)
            // La cuenta activa, arriba del reproductor: es lo que identifica la
            // sesión y va con el resto de las acciones de cuenta, no compitiendo
            // con la navegación en el tope.
            profileCard
                .padding(.bottom, 4)
            // Lo que suena, arriba de las acciones de cuenta: se mira seguido y
            // no debería competir con "Cambiar plataforma" por el último lugar.
            SpotifyMiniPlayer()
                .padding(.bottom, 2)
            if platform == .moodle {
                FooterAction(symbol: "person.badge.plus", label: "Agregar cuenta") {
                    state.addAccount()
                }
            }
            FooterAction(symbol: "arrow.left.arrow.right", label: "Cambiar plataforma") {
                state.backToPicker()
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.sm)
    }
}

private struct FooterAction: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                Text(label).font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovered ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.textPrimary.opacity(hovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Brand mark

/// Sello del códice: una torre almenada grabada en tinta sobre papel. Reemplaza
/// al puente del sistema anterior. Contorno fino, sin relleno chillón.
/// La marca de la app. Ahora es el logotipo real de la UAM, no el castillo
/// dibujado a mano que venía del sistema visual anterior.
///
/// Se conserva el nombre `BrandMark` porque lo usan la barra lateral, la barra
/// de menú y la ventana de cuentas; lo que cambia es qué dibuja.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        UAMMark(size: size)
    }
}

/// Torre del homenaje con almenas. Escala a cualquier tamaño.
private struct Keep: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let x0 = rect.minX, x1 = rect.maxX
        let top = rect.minY, bottom = rect.maxY
        let mer = w / 5   // ancho de cada almena

        // Almenas: sube-baja en el borde superior.
        p.move(to: CGPoint(x: x0, y: top + h * 0.18))
        p.addLine(to: CGPoint(x: x0, y: top))
        p.addLine(to: CGPoint(x: x0 + mer, y: top))
        p.addLine(to: CGPoint(x: x0 + mer, y: top + h * 0.10))
        p.addLine(to: CGPoint(x: x0 + 2*mer, y: top + h * 0.10))
        p.addLine(to: CGPoint(x: x0 + 2*mer, y: top))
        p.addLine(to: CGPoint(x: x0 + 3*mer, y: top))
        p.addLine(to: CGPoint(x: x0 + 3*mer, y: top + h * 0.10))
        p.addLine(to: CGPoint(x: x0 + 4*mer, y: top + h * 0.10))
        p.addLine(to: CGPoint(x: x0 + 4*mer, y: top))
        p.addLine(to: CGPoint(x: x1, y: top))
        p.addLine(to: CGPoint(x: x1, y: top + h * 0.18))

        // Cuerpo hasta la base.
        p.addLine(to: CGPoint(x: x1, y: bottom))
        p.addLine(to: CGPoint(x: x0, y: bottom))
        p.closeSubpath()

        // Portón: arco ojival.
        let gW = w * 0.34, gH = h * 0.40
        let gx = rect.midX - gW/2
        let gy = bottom
        p.move(to: CGPoint(x: gx, y: gy))
        p.addLine(to: CGPoint(x: gx, y: gy - gH * 0.6))
        p.addQuadCurve(to: CGPoint(x: gx + gW/2, y: gy - gH),
                       control: CGPoint(x: gx, y: gy - gH))
        p.addQuadCurve(to: CGPoint(x: gx + gW, y: gy - gH * 0.6),
                       control: CGPoint(x: gx + gW, y: gy - gH))
        p.addLine(to: CGPoint(x: gx + gW, y: gy))
        return p
    }
}

// MARK: - Pinned course row

private struct PinnedCourseRow: View {
    let course: MoodleCourse
    @State private var hovered = false

    var body: some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)

        HStack(spacing: 9) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .shadow(color: accent.opacity(0.6), radius: 3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(info.code)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(info.name)
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.textPrimary.opacity(hovered ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Sidebar row

struct SidebarRow: View {
    let section: AppSection
    let selected: Bool
    var badge: Int? = nil
    let namespace: Namespace.ID

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: section.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? prefs.tint : Palette.textSecondary)
                .frame(width: 20, height: 20)
                .symbolRenderingMode(.hierarchical)

            Text(section.title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let badge {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? prefs.tint : Palette.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(selected ? prefs.tint.opacity(0.16)
                                                : Palette.textPrimary.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
        .background {
            if selected {
                // Una sola pastilla que se desliza entre filas: la transición
                // que hace que el sidebar se sienta continuo y no parpadeante.
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(prefs.tint.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(prefs.tint.opacity(0.22), lineWidth: 0.5)
                    )
                    .matchedGeometryEffect(id: "sidebarSelection", in: namespace)
            } else if hovered {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.textPrimary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
