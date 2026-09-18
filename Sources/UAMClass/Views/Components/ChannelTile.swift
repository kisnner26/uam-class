import SwiftUI

// MARK: - Mosaico
//
// La pieza central de la estética. El menú de la consola no es una lista de
// tarjetas con texto: es una GRILLA DE MOSAICOS grandes, cada uno con su lámina
// de color arriba y su etiqueta abajo, todos del mismo tamaño y todos pulsables.
//
// Reglas que lo hacen sentir físico y no una caja más:
//  · La lámina superior manda. Ocupa dos tercios y lleva el color; la etiqueta
//    vive en una franja blanca abajo, nunca encima del color.
//  · Un solo brillo diagonal cruzando la lámina, que se mueve al pasar el mouse.
//    Es lo que convierte una superficie plana en plástico.
//  · Se levanta al acercarse y se hunde al presionar. Sin eso es un cartel.

struct ChannelTile<Art: View>: View {
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil
    var accent: Color = Palette.accent
    /// Número en la esquina: pendientes, sin leer, lo que sea.
    var badge: Int? = nil
    var aspect: CGFloat = 1.18
    @ViewBuilder var art: () -> Art
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false
    @State private var pressed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                artPlate
                label
            }
            .background(shape.fill(Palette.surface))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(hovered ? accent.opacity(0.55) : Palette.border,
                                   lineWidth: hovered ? 1.6 : 1)
            )
            .shadow(color: accent.opacity(hovered ? 0.28 : 0.10),
                    radius: hovered ? 20 : 8,
                    y: hovered ? 10 : 3)
            .scaleEffect(pressed ? 0.965 : (hovered ? 1.035 : 1))
            .offset(y: hovered && !pressed ? -3 : 0)
            .animation(Motion.spring, value: hovered)
            .animation(Motion.quick, value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { on in
            hovered = on
            if on { SoundKit.shared.play(.hover) }
        }
        #if os(macOS)
        // El "hundido" al presionar es un gesto de mouse: en iPhone, un
        // DragGesture de distancia cero adentro de un ScrollView compite con
        // su pan gesture y termina bloqueando el scroll y el tap.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in
                    pressed = false
                    SoundKit.shared.play(.select)
                }
        )
        #endif
    }

    // MARK: Lámina

    private var artPlate: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            art()

            // Brillo diagonal. Al acercarse cruza la lámina: es el gesto que
            // hace que se vea plástico y encendido.
            GeometryReader { geo in
                let w = geo.size.width
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.34), .white.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.5)
                    .rotationEffect(.degrees(22))
                    .offset(x: hovered ? w * 0.75 : -w * 0.75)
                    .animation(.easeOut(duration: 0.65), value: hovered)
                    .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)

            // Luz alta superior, fija: el volumen del plástico.
            LinearGradient(colors: [.white.opacity(0.30), .clear],
                           startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)

            if let badge, badge > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(min(badge, 99))")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(accent)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Circle().fill(.white))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    Spacer()
                }
                .padding(9)
            }
        }
        .aspectRatio(aspect, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }
}

// MARK: - Láminas listas

/// Inicial gigante recortada por la lámina. Es la carátula por defecto de una
/// materia: legible de lejos y distinta para cada una sin necesidad de arte.
struct GlyphArt: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        ZStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            } else {
                Text(text)
                    .font(.system(size: 74, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
        }
    }
}

/// Franja inferior traslúcida sobre la lámina, para datos sueltos (fecha,
/// contador). Va DENTRO del color, no en la etiqueta blanca.
struct ArtFooter: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.22)))
                Spacer()
            }
        }
        .padding(8)
    }
}
