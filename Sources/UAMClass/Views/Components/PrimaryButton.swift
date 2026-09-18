import SwiftUI

// MARK: - Botón primario
//
// El botón de "sello": tinta plena sobre papel. Sin vidrio ni especular — un
// rótulo estampado. Se oscurece apenas al pasar el mouse, como presionar el
// sello un poco más fuerte.

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var loading: Bool = false
    var disabled: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false
    @State private var pressed = false

    private var tint: Color { prefs.tint }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.textOnAccent)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .regular))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Palette.textOnAccent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 11)
            .padding(.horizontal, Space.md)
            .background(shape.fill(hovered ? Palette.accentHover : Palette.accent))
            .clipShape(shape)
            .elevation(pressed ? .flat : .low)
            .scaleEffect(pressed ? 0.985 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .opacity(disabled ? 0.35 : 1.0)
        .consoleHover($hovered)
        #if os(macOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        #endif
        .animation(Motion.quick, value: hovered)
        .animation(Motion.quick, value: pressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }
}

// MARK: - Botón secundario (vidrio)

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var fullWidth: Bool = true
    let action: () -> Void

    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 10)
            .padding(.horizontal, Space.md)
            .glassBar(radius: Radius.md)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.textPrimary.opacity(hovered ? 0.16 : 0),
                                  lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        #if os(macOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        #endif
        .animation(Motion.quick, value: hovered)
        .animation(Motion.quick, value: pressed)
    }
}

// MARK: - Botón fantasma

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(Type.captionB)
            }
            .foregroundStyle(hovered ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Palette.textPrimary.opacity(hovered ? 0.07 : 0))
            )
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Botón icónico de vidrio

/// Botón circular de vidrio para acciones sueltas (cerrar, favorito, más).
struct GlassIconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color? = nil
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? Palette.textSecondary)
                .frame(width: size, height: size)
                .glassChip(interactive: true)
                .scaleEffect(hovered ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .help(help)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
