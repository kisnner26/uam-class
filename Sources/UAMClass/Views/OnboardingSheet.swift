import SwiftUI

/// Onboarding de la primera vez. Cuatro pantallas, sin fricción, con el mismo
/// ambiente y vidrio que el resto de la app para que no se sienta pegado.
struct OnboardingSheet: View {
    @EnvironmentObject private var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0

    private let pages: [Page] = [
        Page(symbol: "bolt.horizontal.fill", tint: Color(hex: 0x9E2C3A),
             title: "Todo tu Moodle en un lugar",
             body: "Calificaciones, tareas, foros, materiales y personas de cada curso, sin abrir el navegador."),
        Page(symbol: "arrow.down.circle.fill", tint: Color(hex: 0x2E5B62),
             title: "Descargá y previsualizá",
             body: "PDF, imágenes y video se ven inline sin descargar. Cuando querés guardar, se bajan organizados por curso."),
        Page(symbol: "archivebox.fill", tint: Color(hex: 0x8A5F1E),
             title: "Archivá el semestre completo",
             body: "Un click y se baja TODO: materiales, notas en CSV y foros en markdown. Tu propio archivo permanente."),
        Page(symbol: "sparkles", tint: Color(hex: 0x5A3255),
             title: "Superpoderes",
             body: "⌘K para buscar todo, sesiones Pomodoro con estadísticas, avisos de entregas y chat con docentes.")
    ]

    struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            pagination
            footer
        }
        #if os(macOS)
        .frame(width: 520, height: 500)
        #else
        .presentationDetents([.medium])
        #endif
        .background(AmbientBackdrop(tint: pages[page].tint, intensity: 1.0))
    }

    private var content: some View {
        let p = pages[page]
        return VStack(spacing: Space.lg) {
            ZStack {
                // Halo detrás del icono: da el punto focal sin necesitar
                // una ilustración.
                Circle()
                    .fill(p.tint.opacity(0.28))
                    .frame(width: 130, height: 130)
                    .blur(radius: 34)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(p.tint.brandGradient)
                    .frame(width: 78, height: 78)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Palette.rimOnDark, lineWidth: 1)
                    )
                    .shadow(color: p.tint.opacity(0.45), radius: 20, x: 0, y: 10)

                Image(systemName: p.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 52)

            VStack(spacing: Space.xs) {
                Text(p.title)
                    .displayStyle(23, weight: .bold)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3.5)
                    .frame(maxWidth: 390)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.lg)

            Spacer(minLength: 0)
        }
        .id(page)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24)),
            removal: .opacity.combined(with: .offset(x: -24))
        ))
        .animation(Motion.spring, value: page)
    }

    private var pagination: some View {
        HStack(spacing: 5) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(page == i ? pages[i].tint : Palette.textPrimary.opacity(0.16))
                    .frame(width: page == i ? 22 : 6, height: 6)
                    .animation(Motion.spring, value: page)
                    .onTapGesture {
                        withAnimation(Motion.spring) { page = i }
                    }
            }
        }
        .padding(.vertical, Space.sm)
    }

    private var footer: some View {
        HStack {
            GhostButton(title: "Omitir") { dismiss() }
            Spacer()
            PrimaryButton(title: page < pages.count - 1 ? "Siguiente" : "Empezar",
                          icon: page < pages.count - 1 ? "arrow.right" : "checkmark",
                          fullWidth: false) {
                if page < pages.count - 1 {
                    withAnimation(Motion.spring) { page += 1 }
                } else {
                    dismiss()
                }
            }
            .frame(width: 132)
        }
        .padding(Space.md)
    }
}
