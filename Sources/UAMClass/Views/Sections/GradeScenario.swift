import SwiftUI

// MARK: - Calculadora de escenarios
//
// La pregunta que uno se hace en la mitad del semestre y no tiene dónde
// responder: *¿cuánto necesito en el corte que falta?*
//
// Moodle da el acumulado del curso, pero no razona hacia adelante. Acá se
// escriben los cortes que ya salieron y se calcula lo que falta para los 210
// (aprobar) y para los 180 (convocatoria). Ver "necesitás 78" es otra cosa que
// ver "llevás 132".

struct GradeScenarioCard: View {
    let courseCode: String
    let courseName: String

    @EnvironmentObject private var prefs: UserPrefs
    /// Nota de cada corte, sobre 100. Vacío = todavía no salió.
    @State private var cortes: [String] = ["", "", ""]

    private var entered: [Double] {
        cortes.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }
    private var pending: Int { cortes.filter { Double($0.replacingOccurrences(of: ",", with: ".")) == nil }.count }
    private var earned: Double { entered.reduce(0, +) }

    /// Cuánto hace falta, por corte, para llegar a un total.
    private func needed(for target: Double) -> Double? {
        guard pending > 0 else { return nil }
        return (target - earned) / Double(pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 12))
                    .foregroundStyle(prefs.tint)
                Text("¿Cuánto necesito?")
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Text("\(Int(earned.rounded())) / 300")
                    .font(Type.mono)
                    .foregroundStyle(Palette.textSecondary)
            }

            HStack(spacing: Space.xs) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(i + 1)er corte").labelCaps()
                        TextField("—", text: Binding(
                            get: { cortes[i] },
                            set: { cortes[i] = String($0.prefix(5)) }
                        ))
                        .textFieldStyle(.plain)
                        .font(Type.body)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.textPrimary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1))
                    }
                }
            }

            verdict
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    @ViewBuilder
    private var verdict: some View {
        if entered.isEmpty {
            Text("Escribí las notas de los cortes que ya salieron, sobre 100.")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
        } else if pending == 0 {
            // Semestre cerrado: ya no hay nada que calcular, solo veredicto.
            let standing = UAMGrading.standing(percent: earned / 3)
            row(icon: standing.symbol, tone: standing.tone,
                text: "Cerrado con \(Int(earned.rounded())) puntos — \(String(format: "%.1f", earned / 3)) promediado. \(standing.label).")
        } else {
            let pass = needed(for: UAMGrading.passingPoints)!
            let conv = needed(for: UAMGrading.convocatoriaPoints)!
            let label = pending == 1 ? "en el corte que falta"
                                     : "en cada uno de los \(pending) cortes que faltan"

            if pass <= 0 {
                row(icon: "checkmark.seal.fill", tone: Palette.success,
                    text: "Ya tenés los 210. Aprobaste sin depender de lo que falta.")
            } else if pass > 100 {
                // Lo importante no es que "no alcanza", sino si todavía hay
                // convocatoria: eso cambia qué hacés el resto del semestre.
                if conv > 0 && conv <= 100 {
                    row(icon: "arrow.clockwise.circle.fill", tone: Palette.warning,
                        text: "Los 210 ya son inalcanzables. Para convocatoria necesitás \(fmt(conv)) \(label).")
                } else {
                    row(icon: "xmark.seal.fill", tone: Palette.danger,
                        text: "Ni los 210 ni los 180 son alcanzables con lo que queda.")
                }
            } else {
                row(icon: "target", tone: prefs.tint,
                    text: "Necesitás \(fmt(pass)) \(label) para llegar a 210 y aprobar.")
                if conv > 0 {
                    row(icon: "arrow.clockwise.circle", tone: Palette.textTertiary,
                        text: "Con \(fmt(conv)) te queda convocatoria (180).")
                }
            }
        }
    }

    private func row(icon: String, tone: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tone)
                .frame(width: 14)
            Text(text)
                .font(Type.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func fmt(_ v: Double) -> String {
        String(format: v == v.rounded() ? "%.0f" : "%.1f", v)
    }
}
