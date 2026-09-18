import SwiftUI

// MARK: - Píldoras y badges

/// Etiqueta de estado. `tone` decide el color; el fondo es siempre el tinte
/// al 12–16%, nunca saturado, para que diez pills juntas no griten.
struct Pill: View {
    enum Tone { case neutral, accent, success, warning, danger, custom(Color) }

    let text: String
    var icon: String? = nil
    var tone: Tone = .neutral
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 0.5))
    }

    private var color: Color {
        switch tone {
        case .neutral:        return Palette.textSecondary
        case .accent:         return Palette.accent
        case .success:        return Palette.success
        case .warning:        return Palette.warning
        case .danger:         return Palette.danger
        case .custom(let c):  return c
        }
    }
}

/// Contador chico al lado de un título de bloque.
struct CountBadge: View {
    let value: Int
    init(_ value: Int) { self.value = value }

    var body: some View {
        Text("\(value)")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Palette.textPrimary.opacity(0.07)))
    }
}

/// Tecla de atajo dibujada como tecla.
struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textSecondary)
            .frame(minWidth: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.textPrimary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.textPrimary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// Icono (o sigla) dentro de una pastilla de color. El bloque de construcción
/// de casi todas las filas de la app.
struct IconTile: View {
    var symbol: String? = nil
    /// Alternativa al símbolo: hasta 3 caracteres, para códigos de materia.
    var text: String? = nil
    var tint: Color = Palette.accent
    var size: CGFloat = 32
    var filled: Bool = false

    init(symbol: String, tint: Color = Palette.accent,
         size: CGFloat = 32, filled: Bool = false) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
        self.filled = filled
    }

    init(text: String, tint: Color = Palette.accent,
         size: CGFloat = 32, filled: Bool = false) {
        self.text = text
        self.tint = tint
        self.size = size
        self.filled = filled
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            shape.fill(filled ? AnyShapeStyle(tint.brandGradient)
                              : AnyShapeStyle(tint.opacity(0.14)))
            shape.strokeBorder(filled ? Color.white.opacity(0.22) : tint.opacity(0.18),
                               lineWidth: 0.5)

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(filled ? Color.white : tint)
            } else if let text {
                Text(text)
                    .font(.system(size: size * 0.30, weight: .bold))
                    .foregroundStyle(filled ? Color.white : tint)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Segmentado de vidrio

/// Selector segmentado con el indicador hecho de vidrio que se desliza entre
/// opciones (morphing real en macOS 26).
struct GlassSegmented<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let label: String
        let symbol: String?
        var id: some Hashable { value }

        init(_ value: T, label: String, symbol: String? = nil) {
            self.value = value
            self.label = label
            self.symbol = symbol
        }
    }

    @Binding var selection: T
    let options: [Option]
    /// Solo iconos, sin texto. Para toolbars apretadas.
    var iconsOnly: Bool = false

    @EnvironmentObject private var prefs: UserPrefs
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let active = opt.value == selection
                Button {
                    withAnimation(Motion.spring) { selection = opt.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = opt.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        if !iconsOnly {
                            Text(opt.label)
                                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                        }
                    }
                    .foregroundStyle(active ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, iconsOnly ? 8 : 11)
                    .padding(.vertical, 5)
                    .frame(minWidth: iconsOnly ? 28 : 0)
                    .background {
                        if active {
                            Capsule()
                                .fill(prefs.tint.opacity(0.16))
                                .overlay(Capsule().strokeBorder(prefs.tint.opacity(0.28),
                                                                lineWidth: 0.5))
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(opt.label)
            }
        }
        .padding(2.5)
        .glassChip(interactive: false)
    }
}

// MARK: - Métrica

/// Tile de estadística del dashboard. Cifra grande en rounded, etiqueta abajo,
/// y una barra de acento al costado que ancla el color.
struct MetricTile: View {
    @EnvironmentObject private var prefs: UserPrefs
    let icon: String
    let label: String
    let value: String
    var tint: Color = Palette.accent
    var caption: String? = nil

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Space.sm) {
            IconTile(symbol: icon, tint: tint, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(Type.metric(prefs.density == .compact ? 18 : 21))
                    .foregroundStyle(value == "—" ? Palette.textSecondary : Palette.textPrimary)
                    .metricDigits()
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                if let caption {
                    Text(caption)
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, prefs.density == .compact ? Space.xs : Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSurface(prefs, cornerRadius: Radius.md,
                         elevation: hovered ? .mid : .low)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 2.5)
                .padding(.vertical, 10)
                .opacity(hovered ? 1 : 0.5)
        }
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Barra de progreso

/// Barra fina con relleno degradado. Reemplaza al ProgressView del sistema
/// cuando el color importa.
struct AccentBar: View {
    let value: Double          // 0…1
    var tint: Color = Palette.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.textPrimary.opacity(0.08))
                Capsule()
                    .fill(tint.brandGradient)
                    .frame(width: max(height, geo.size.width * max(0, min(1, value))))
                    .shadow(color: tint.opacity(0.35), radius: 4, x: 0, y: 1)
            }
        }
        .frame(height: height)
        .animation(Motion.spring, value: value)
    }
}
