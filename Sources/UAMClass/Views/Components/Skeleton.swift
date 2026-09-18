import SwiftUI

/// Placeholder con barrido de luz. El barrido va en diagonal y con un
/// gradiente de tres paradas: un rectángulo que parpadea se lee como bug.
struct Skeleton: View {
    var cornerRadius: CGFloat = Radius.xs
    var height: CGFloat = 12
    var width: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.2

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Palette.textPrimary.opacity(0.07))
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Palette.textPrimary.opacity(0.08), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(x: 0.6, anchor: .leading)
                    .offset(x: phase * (width ?? 240))
                    .clipShape(shape)
            }
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 2.0
                }
            }
    }
}

struct SkeletonCourseCard: View {
    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Skeleton(cornerRadius: 0, height: 96)
            VStack(alignment: .leading, spacing: 9) {
                Skeleton(cornerRadius: 4, height: 8, width: 64)
                Skeleton(cornerRadius: 4, height: 13, width: 180)
                Skeleton(cornerRadius: 4, height: 13, width: 116)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Skeleton(cornerRadius: 5, height: 15, width: 58)
                    Spacer()
                    Skeleton(cornerRadius: 5, height: 15, width: 22)
                }
            }
            .padding(prefs.padLarge)
        }
        .frame(minHeight: 220, alignment: .topLeading)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }
}

/// Fila de placeholder para listas.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Space.sm) {
            Skeleton(cornerRadius: 9, height: 34, width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Skeleton(cornerRadius: 3, height: 9, width: 70)
                Skeleton(cornerRadius: 3, height: 12, width: 200)
            }
            Spacer()
            Skeleton(cornerRadius: 3, height: 10, width: 48)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
    }
}
