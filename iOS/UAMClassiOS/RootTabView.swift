import SwiftUI

/// Equivalente iPhone de `MainWindow` (macOS): en vez de un `NavigationSplitView`
/// con sidebar, una `TabView` con una `NavigationStack` propia por pestaña.
///
/// El MVP de iPhone cubre un subconjunto de `AppSection`: Inicio, Materias,
/// Calificaciones, Tareas y Horario para Moodle; Horario y Notas académicas
/// para CLASS Portal. El resto de las secciones de escritorio (Exámenes,
/// Estudiar, Directorio, Estadísticas, menú de Claude, Spotify…) quedan para
/// una próxima pasada.
///
/// Mensajes NO es una pestaña: a partir de la sexta, `TabView` en iPhone
/// las esconde todas detrás de un "More" (en inglés, sin traducir) — que es
/// justo donde el horario se había perdido. Se accede como botón en la
/// barra de Inicio en su lugar.
struct RootTabView: View {
    let platform: Platform
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var selection: AppSection = .dashboard
    @State private var navPath = NavigationPath()
    @State private var showSettings = false
    @State private var showMensajes = false

    private var tabs: [AppSection] {
        switch platform {
        case .moodle:      return [.dashboard, .materias, .notasMoodle, .asignaciones, .horario]
        case .classPortal: return [.horario, .notasClass]
        }
    }

    /// Solo Inicio y Materias empujan el detalle de curso sobre su propio path;
    /// las demás pestañas usan un `NavigationPath` vacío fijo.
    private func path(for section: AppSection) -> Binding<NavigationPath> {
        (section == .materias || section == .dashboard) ? $navPath : .constant(NavigationPath())
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(tabs) { section in
                NavigationStack(path: path(for: section)) {
                    sectionRoot(section)
                        .navigationTitle(section.title)
                        .toolbar {
                            if section == .dashboard, platform == .moodle {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        showMensajes = true
                                    } label: {
                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                    }
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showSettings = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                }
                            }
                        }
                        .navigationDestination(for: MoodleCourse.self) { course in
                            CourseDetailView(course: course)
                        }
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
            }
        }
        .onAppear {
            if !tabs.contains(selection) { selection = tabs.first ?? .dashboard }
        }
        .onChange(of: state.pendingCourseOpen) { _, course in
            guard let course else { return }
            state.pendingCourseOpen = nil
            selection = .materias
            var fresh = NavigationPath()
            fresh.append(course)
            navPath = fresh
        }
        .onChange(of: state.pendingSectionOpen) { _, section in
            guard let section, tabs.contains(section) else { return }
            selection = section
            state.pendingSectionOpen = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsViewIOS()
                .environmentObject(state)
                .environmentObject(prefs)
        }
        .sheet(isPresented: $showMensajes) {
            NavigationStack {
                MensajesView()
                    .navigationTitle("Mensajes")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { showMensajes = false }
                        }
                    }
            }
            .environmentObject(state)
            .environmentObject(prefs)
        }
    }

    @ViewBuilder private func sectionRoot(_ section: AppSection) -> some View {
        switch section {
        case .dashboard:    DashboardView()
        case .materias:     MateriasView()
        case .notasMoodle:  NotasView()
        case .asignaciones: AsignacionesView()
        case .horario:      HorarioView()
        case .notasClass:   NotasAcademicasView()
        default:            EmptyView()
        }
    }
}
