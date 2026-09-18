import SwiftUI

// MARK: - Superficies del códice
//
// El sistema anterior era Liquid Glass. En el manuscrito NO hay vidrio: hay
// papel, vitela y reglas de tinta. Se conservan los nombres de los
// modificadores (`glassPanel`, `glassBar`, `glassChip`, `contentCard`…) para no
// tocar cada vista; lo que devuelven ahora son hojas planas con filos finos.
//
// Regla de jerarquía:
//   contentCard → hoja de contenido, borde hairline, sombra mínima.
//   glassBar    → panel de navegación adherido (sidebar, toolbar): vitela mate.
//   glassPanel  → hoja flotante (palette, toasts, popovers): vitela + sombra.
//   glassChip   → píldora con filo de tinta.

// MARK: Formas

extension View {
    @ViewBuilder
    func containerRadius(_ radius: CGFloat) -> some View {
        self.containerShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// El códice no usa esquinas concéntricas del sistema; radio fijo continuo.
func ConcentricShape(fallback radius: CGFloat, minimum: CGFloat = 6) -> AnyShape {
    AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
}

// MARK: Modificadores de superficie

extension View {

    /// Hoja flotante de vitela. Para lo que se posa por encima de la página.
    func glassPanel(radius: CGFloat = Radius.lg,
                    tint: Color? = nil,
                    interactive: Bool = false,
                    elevation: Elevation = .floating) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Palette.surfaceElevated))
            .overlay(shape.strokeBorder(Palette.borderStrong, lineWidth: 1))
            .clipShape(shape)
            .containerShape(shape)
            .elevation(elevation)
    }

    /// Vitela mate para paneles de navegación adheridos a un borde.
    func glassBar(radius: CGFloat = Radius.md, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .clipShape(shape)
            .containerShape(shape)
    }

    /// Píldora con filo de tinta.
    func glassChip(tint: Color? = nil, interactive: Bool = true) -> some View {
        self
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .clipShape(Capsule())
    }

    /// Hoja de contenido: la base de casi todo. Plana, filo hairline, sombra
    /// apenas perceptible — una página apoyada sobre otra.
    func contentCard(radius: CGFloat = Radius.md,
                     elevation: Elevation = .low,
                     stroke: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Palette.surface))
            .overlay {
                if stroke { shape.strokeBorder(Palette.border, lineWidth: 1) }
            }
            .clipShape(shape)
            .containerShape(shape)
            .elevation(elevation)
    }

    /// Sin brillo especular en papel: no-op, se conserva la firma.
    func specularTop(radius: CGFloat = Radius.md) -> some View { self }

    @ViewBuilder
    func sidebarBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }

    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

// MARK: Agrupación (sin fusión de vidrio: pasa a través)

@ViewBuilder
func GlassGroup<Content: View>(spacing: CGFloat = 8,
                               @ViewBuilder content: () -> Content) -> some View {
    content()
}

extension View {
    func glassID(_ id: some Hashable, in namespace: Namespace.ID) -> some View { self }
    func glassUnion(_ id: some Hashable, in namespace: Namespace.ID) -> some View { self }
    func glassMorph() -> some View { self }
}

// MARK: Estilos de botón

/// Botón "de sello": tinta plena sobre papel, o papel con filo. Sin vidrio.
struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color? = nil

    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Space.md)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Palette.textOnAccent : Palette.textPrimary)
            .background {
                Capsule().fill(prominent ? Palette.accent : Palette.surface)
                // El brillo plástico del mosaico de consola: una luz sobre la
                // mitad de arriba, nunca sobre todo el botón.
                Capsule().fill(Palette.specular).opacity(prominent ? 0.5 : 0.85)
            }
            .overlay {
                Capsule().strokeBorder(prominent ? Color.white.opacity(0.35)
                                                 : Palette.borderStrong,
                                       lineWidth: 1)
            }
            .shadow(color: (prominent ? Palette.accent : Color.black)
                        .opacity(configuration.isPressed ? 0.08 : (hovered ? 0.24 : 0.12)),
                    radius: configuration.isPressed ? 2 : (hovered ? 8 : 4),
                    y: configuration.isPressed ? 0 : 2)
            .scaleEffect(configuration.isPressed ? 0.96 : (hovered ? 1.03 : 1))
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: hovered)
            .onHover { on in
                hovered = on
                if on { SoundKit.shared.play(.hover) }
            }
            // El sonido va al PRESIONAR, no al soltar: así acompaña al dedo en
            // vez de llegar tarde.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundKit.shared.play(prominent ? .confirm : .select) }
            }
    }
}

extension View {
    /// El estilo nativo de vidrio ya no aplica; se usa el de sello.
    func nativeGlassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(GlassButtonStyle(prominent: prominent))
    }
}

// MARK: Compat

enum GlassIntensity {
    case clear, regular
    var materialFallback: Material {
        switch self {
        case .clear:   return .ultraThinMaterial
        case .regular: return .regularMaterial
        }
    }
}

extension View {
    func liquidGlass(_ intensity: GlassIntensity = .regular,
                     shape: some Shape = RoundedRectangle(cornerRadius: Radius.md,
                                                          style: .continuous)) -> some View {
        self
            .background(shape.fill(Palette.surface))
            .overlay(shape.stroke(Palette.border, lineWidth: 1))
    }

    func liquidGlassInteractive(shape: some Shape = RoundedRectangle(cornerRadius: Radius.md,
                                                                    style: .continuous)) -> some View {
        self
            .background(shape.fill(Palette.surface))
            .overlay(shape.stroke(Palette.border, lineWidth: 1))
    }
}
