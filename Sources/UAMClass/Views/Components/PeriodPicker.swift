import SwiftUI

/// Selector de semestre.
///
/// Vive en la BARRA DE HERRAMIENTAS, no en el sidebar. El semestre es un
/// contexto global —reencuadra materias, tareas, notas, exámenes y asistencia a
/// la vez—, y ese es el lugar que macOS reserva para el alcance de la ventana.
/// Abajo del todo quedaba escondido, y su menú se abría hacia arriba tapando
/// media barra lateral.
struct PeriodPicker: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    var body: some View {
        Menu {
            menuItems
        } label: {
            // En la toolbar, la etiqueta nativa. El menú de macOS ya dibuja el
            // fondo y el indicador; poner la píldora propia encima se veía como
            // un botón dentro de otro botón.
            Label(compactLabel, systemImage: "calendar")
        }
        .menuStyle(.automatic)
        // Sin esto macOS colapsa el menú a puro ícono y se pierde el semestre,
        // que es exactamente el dato que el control existe para mostrar.
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help(helpText)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button { state.periodScope = .current } label: {
            Label(currentLabel, systemImage: state.periodScope == .current ? "checkmark" : "")
        }
        Button { state.periodScope = .previous } label: {
            Label("Semestres anteriores",
                  systemImage: state.periodScope == .previous ? "checkmark" : "")
        }
        Button { state.periodScope = .all } label: {
            Label("Todos los semestres",
                  systemImage: state.periodScope == .all ? "checkmark" : "")
        }

        if state.availablePeriods.count > 1 {
            Divider()
            ForEach(state.availablePeriods) { p in
                Button {
                    state.periodScope = .specific(p)
                } label: {
                    Label(p.longLabel,
                          systemImage: state.periodScope == .specific(p) ? "checkmark" : "")
                }
            }
        }
    }

    /// Corto, porque va en una barra con otros seis controles.
    private var compactLabel: String {
        switch state.periodScope {
        case .current:         return state.currentPeriod?.label ?? "Semestre"
        case .previous:        return "Anteriores"
        case .all:             return "Todos"
        case .specific(let p): return p.label
        }
    }

    /// Con el semestre detectado, "Actual" se vuelve concreto: "I Sem 2026".
    private var currentLabel: String {
        state.currentPeriod.map { "Actual · \($0.label)" } ?? "Semestre actual"
    }

    private var helpText: String {
        let hidden = state.hiddenCourseCount
        if hidden == 0 { return "Filtrar por semestre" }
        return "Mostrando \(state.visibleCourses.count) de \(state.courses.count) materias · \(hidden) fuera de este semestre"
    }
}
