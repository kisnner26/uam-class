import SwiftUI

/// Splash de arranque para iPhone. Igual en espíritu al de macOS
/// (`App/UAMClassApp.swift`), pero usando `UAMMark` en vez de `BrandMark`
/// (que vive en `MainWindow.swift`, exclusivo de Mac).
struct SplashView: View {
    @EnvironmentObject private var prefs: UserPrefs
    @State private var appear = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: prefs.tint, intensity: 1.15)

            VStack(spacing: Space.md) {
                UAMMark(size: 64, plated: true)
                    .scaleEffect(appear ? 1 : 0.86)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 4) {
                    Text("UAM Class")
                        .displayStyle(22, weight: .semibold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Conectando con el portal")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 6)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(prefs.tint.brandGradient)
                        .frame(width: 48)
                        .offset(x: sweep ? 92 : -48)
                        .shadow(color: prefs.tint.opacity(0.5), radius: 6)
                }
                .frame(width: 140, height: 4)
                .clipShape(Capsule())
                .padding(.top, Space.xs)
                .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(Motion.spring) { appear = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }
}
