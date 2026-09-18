import SwiftUI

struct ArancelesView: View {
    var body: some View {
        PortalPlaceholder(
            title: "Aranceles",
            eyebrow: "CLASS Portales",
            subtitle: "Estado de cuenta y pagos del período",
            icon: "creditcard.fill",
            bullets: [
                "Saldo pendiente y fechas de corte",
                "Detalle de cuotas y recargos",
                "Historial de pagos aplicados"
            ],
            source: "estudiantes/principalCajas.aspx"
        )
    }
}
