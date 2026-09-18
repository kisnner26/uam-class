import SwiftUI

/// Selector de plataforma. Es la primera pantalla que ve alguien, así que
/// carga todo el peso del lenguaje visual: el fondo vivo detrás y dos
/// mosaicos grandes con la misma gramática que el menú de Inicio.
struct PlatformPickerView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var appeared = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: prefs.tint, intensity: 1.2)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(Motion.spring.delay(0.05)) { appeared = true }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)

            VStack(spacing: Space.xl) {
                header
                cards
                footer
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, Space.xl)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)

            Spacer(minLength: Space.xl)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.xs) {
            // El logotipo real, no un icono del sistema. Es lo primero que se ve
            // al abrir la app: tiene que ser la marca de verdad.
            UAMLogo(height: 68)
                .shadow(color: Palette.bay.opacity(0.22), radius: 18, y: 6)

            Text("Class")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2)

            Text("Elegí a dónde entrar")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: Paneles
    //
    // Dos mosaicos grandes, no dos fichas de texto. Misma gramática que el menú:
    // lámina de color arriba con el símbolo, franja blanca abajo con el nombre.

    private var cards: some View {
        HStack(spacing: Space.md) {
            PlatformPanel(
                title: "UAM Virtual",
                eyebrow: "AULA VIRTUAL · MOODLE",
                blurb: "Materias, entregas, calificaciones y foros.",
                symbol: "graduationcap.fill",
                accent: Palette.bay,
                features: ["Materias con contenido", "Notas y calificaciones",
                           "Foros y mensajes", "Asignaciones y entregas"],
                action: { state.choosePlatform(.moodle) }
            )

            PlatformPanel(
                title: "UAM Class",
                eyebrow: "REGISTRO ACADÉMICO",
                blurb: "Horario oficial, notas y estado de aranceles.",
                symbol: "building.columns.fill",
                accent: Palette.accent,
                features: ["Horario oficial", "Notas académicas",
                           "Estado de aranceles", "Datos personales"],
                action: { state.choosePlatform(.classPortal) }
            )
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text("Tus credenciales solo se usan para autenticar. El PIN nunca se guarda.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Palette.textQuaternary)
    }
}

// MARK: - Panel de plataforma

private struct PlatformPanel: View {
    let title: String
    let eyebrow: String
    let blurb: String
    let symbol: String
    let accent: Color
    let features: [String]
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false
    @State private var pressed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                plate
                details
            }
            .background(shape.fill(Palette.surface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(hovered ? accent.opacity(0.5) : Palette.border,
                                        lineWidth: hovered ? 1.8 : 1))
            .shadow(color: accent.opacity(hovered ? 0.30 : 0.12),
                    radius: hovered ? 26 : 12, y: hovered ? 12 : 5)
            .scaleEffect(pressed ? 0.975 : (hovered ? 1.025 : 1))
            .offset(y: hovered && !pressed ? -4 : 0)
            .animation(Motion.spring, value: hovered)
            .animation(Motion.quick, value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { on in
            hovered = on
            if on { SoundKit.shared.play(.hover) }
        }
        #if os(macOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false; SoundKit.shared.play(.confirm) }
        )
        #endif
    }

    private var plate: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.70)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            GeometryReader { geo in
                let w = geo.size.width
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.32),
                                                  .white.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.45)
                    .rotationEffect(.degrees(22))
                    .offset(x: hovered ? w * 0.8 : -w * 0.8)
                    .animation(.easeOut(duration: 0.7), value: hovered)
                    .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)

            LinearGradient(colors: [.white.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .frame(height: 132)
        .clipped()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(eyebrow)
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(accent)

            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)

            Text(blurb)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(features, id: \.self) { f in
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(accent)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(accent.opacity(0.14)))
                        Text(f)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .padding(.top, 2)

            HStack(spacing: 5) {
                Text("Entrar")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .offset(x: hovered ? 3 : 0)
            }
            .foregroundStyle(accent)
            .padding(.top, 4)
            .animation(Motion.quick, value: hovered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
    }
}
