import SwiftUI

struct NotasAcademicasView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        PortalPlaceholder(
            title: "Notas académicas",
            eyebrow: "CLASS Portales",
            subtitle: "El historial oficial del registro, no el de Moodle",
            icon: "graduationcap.fill",
            bullets: [
                "Calificaciones finales por período",
                "Índice acumulado y créditos aprobados",
                "Historial completo de la carrera"
            ],
            source: "estudiantes/CalificacionesV2.aspx"
        )
    }
}
