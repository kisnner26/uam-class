import SwiftUI

/// Card con rating de dificultad de 5 estrellas.
struct RatingCard: View {
    let courseId: Int
    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dificultad").labelCaps()
                Text(descriptor)
                    .font(Type.subtitle)
                    .foregroundStyle(store.rating(for: courseId) == 0
                                     ? Palette.textTertiary : Palette.textPrimary)
                    .contentTransition(.opacity)
                Text("Tu percepción personal · solo local")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            starPicker
        }
        .padding(Space.md)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private var descriptor: String {
        switch store.rating(for: courseId) {
        case 1: return "Muy fácil"
        case 2: return "Fácil"
        case 3: return "Moderado"
        case 4: return "Difícil"
        case 5: return "Muy difícil"
        default: return "Sin calificar"
        }
    }

    private var starPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                StarButton(filled: store.rating(for: courseId) >= i, index: i) {
                    // Click en la misma estrella la desactiva.
                    withAnimation(Motion.pop) {
                        if store.rating(for: courseId) == i {
                            store.setRating(0, for: courseId)
                        } else {
                            store.setRating(i, for: courseId)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassChip(interactive: false)
    }
}

private struct StarButton: View {
    let filled: Bool
    let index: Int
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: filled ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? Palette.gold : Palette.textQuaternary)
                .shadow(color: Palette.gold.opacity(filled ? 0.45 : 0), radius: 5)
                .scaleEffect(hovered ? 1.2 : 1.0)
                .symbolEffect(.bounce, value: filled)
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.pop, value: hovered)
        .help("\(index) de 5")
    }
}
