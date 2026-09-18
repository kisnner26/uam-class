import SwiftUI

// MARK: - Card de contenido

/// Superficie estándar para contenido. El fondo respeta la preferencia de
/// densidad y de vidrio del usuario; el radio es concéntrico con sus hijos.
struct Card<Content: View>: View {
    @EnvironmentObject private var prefs: UserPrefs
    var padding: CGFloat? = nil
    var cornerRadius: CGFloat = Radius.lg
    var elevation: Elevation = .low
    let content: () -> Content

    init(padding: CGFloat? = nil,
         cornerRadius: CGFloat = Radius.lg,
         elevation: Elevation = .low,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevation = elevation
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding ?? prefs.padLarge)
            .adaptiveSurface(prefs, cornerRadius: cornerRadius, elevation: elevation)
    }
}

/// Card que reacciona al mouse: se levanta, gana sombra y enciende un rim de
/// color. Para cualquier card que sea, en el fondo, un botón.
struct HoverCard<Content: View>: View {
    @EnvironmentObject private var prefs: UserPrefs
    var accent: Color = Palette.accent
    var cornerRadius: CGFloat = Radius.lg
    var padding: CGFloat? = nil
    @ViewBuilder let content: (Bool) -> Content

    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content(hovered)
            .padding(padding ?? prefs.padLarge)
            .adaptiveSurface(prefs, cornerRadius: cornerRadius,
                             elevation: hovered ? .high : .low)
            .overlay {
                shape.strokeBorder(accent.opacity(hovered ? 0.42 : 0), lineWidth: 1)
            }
            .shadow(color: accent.opacity(hovered ? 0.18 : 0),
                    radius: hovered ? 22 : 0, x: 0, y: 10)
            .scaleEffect(hovered ? 1.006 : 1)
            .offset(y: hovered ? -2 : 0)
            .consoleHover($hovered)
            .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Panel flotante

/// Vidrio real. Solo para cosas que flotan por encima de la app.
struct GlassPanel<Content: View>: View {
    var radius: CGFloat = Radius.xl
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .glassPanel(radius: radius, tint: tint)
    }
}

// MARK: - Estado vacío

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        VStack(spacing: Space.sm) {
            ZStack {
                Circle()
                    .fill(prefs.tint.opacity(0.10))
                Circle()
                    .strokeBorder(prefs.tint.opacity(0.16), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(prefs.tint.opacity(0.85))
            }
            .frame(width: 56, height: 56)
            .padding(.bottom, 2)

            Text(title)
                .font(Type.subtitle)
                .foregroundStyle(Palette.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .nativeGlassButton()
                    .controlSize(.regular)
                    .tint(prefs.tint)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

// MARK: - Encabezados

/// Encabezado grande de pantalla, al modo del códice: la versalita (cejilla) va
/// precedida de un filete de tinta — la inscripción que abre el capítulo — y el
/// título en serif con tracking abierto.
struct SectionHeader: View {
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            // Barra de acento a la izquierda: ancla el título como el rótulo de
            // una pantalla de sistema, no como un <h1> de página web.
            Capsule()
                .fill(LinearGradient(colors: [prefs.tint, prefs.tint.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(prefs.tint)
                }
                Text(title)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.vertical, 2)

            Spacer(minLength: Space.sm)

            if let trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

struct BlockHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)

            if let count {
                CountBadge(count)
            }

            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension BlockHeader where Trailing == EmptyView {
    init(icon: String, title: String, count: Int? = nil) {
        self.init(icon: icon, title: title, count: count, trailing: { EmptyView() })
    }
}
