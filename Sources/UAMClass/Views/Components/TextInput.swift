import SwiftUI

/// Campo de texto con etiqueta en versalitas y anillo de foco de dos capas
/// (halo suave + borde nítido), como los campos del sistema en Tahoe.
struct TextInput: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var icon: String? = nil

    @EnvironmentObject private var prefs: UserPrefs
    @FocusState private var focused: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).labelCaps()

            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(focused ? prefs.tint : Palette.textTertiary)
                        .frame(width: 14)
                }

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 10)
            .background(shape.fill(Palette.textPrimary.opacity(0.045)))
            .overlay(
                shape.strokeBorder(focused ? prefs.tint.opacity(0.75) : Palette.border,
                                   lineWidth: focused ? 1.2 : 0.5)
            )
            .background(
                // Halo de foco. Va detrás para que no recorte el texto.
                shape
                    .fill(prefs.tint.opacity(focused ? 0.16 : 0))
                    .blur(radius: 7)
                    .padding(-2)
            )
            .clipShape(shape)
            .animation(Motion.quick, value: focused)
        }
    }
}

/// Campo de búsqueda inline para toolbars y encabezados de sección.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Buscar"
    /// `nil` deja que el campo ocupe todo el ancho disponible.
    var width: CGFloat? = 190

    @EnvironmentObject private var prefs: UserPrefs
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focused ? prefs.tint : Palette.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Type.caption)
                .focused($focused)
                .frame(width: width)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassChip(interactive: false)
        .overlay(
            Capsule().strokeBorder(prefs.tint.opacity(focused ? 0.55 : 0), lineWidth: 1)
        )
        .animation(Motion.quick, value: focused)
        .animation(Motion.quick, value: text.isEmpty)
    }
}
