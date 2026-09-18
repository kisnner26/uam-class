import SwiftUI

/// Creador de Mii: el retrato arriba, las piezas abajo.
///
/// El retrato queda SIEMPRE visible mientras elegís, porque el editor entero
/// existe para ver el efecto de cada cambio. Si hubiera que hacer scroll para
/// mirar la cara, cada elección sería a ciegas.
struct MiiEditor: View {
    /// Cuenta a la que pertenece este Mii.
    let accountID: String
    let displayName: String

    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LocalStore.shared

    @State private var mii = Mii()
    @State private var tab: Part = .cara

    enum Part: String, CaseIterable, Identifiable {
        case cara, pelo, ojos, cejas, nariz, boca, barba, lentes, fondo
        var id: String { rawValue }

        var label: String {
            switch self {
            case .cara:   return "Cara"
            case .pelo:   return "Pelo"
            case .ojos:   return "Ojos"
            case .cejas:  return "Cejas"
            case .nariz:  return "Nariz"
            case .boca:   return "Boca"
            case .barba:  return "Barba"
            case .lentes: return "Lentes"
            case .fondo:  return "Fondo"
            }
        }

        var symbol: String {
            switch self {
            case .cara:   return "face.smiling"
            case .pelo:   return "comb"
            case .ojos:   return "eye"
            case .cejas:  return "eyebrow"
            case .nariz:  return "nose"
            case .boca:   return "mouth"
            case .barba:  return "mustache"
            case .lentes: return "eyeglasses"
            case .fondo:  return "circle.righthalf.filled"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            portrait
            Divider().overlay(Palette.divider)
            tabBar
            Divider().overlay(Palette.divider)
            ScrollView { options.padding(Space.md) }
                .scrollContentBackground(.hidden)
            Divider().overlay(Palette.divider)
            footer
        }
        .frame(width: 560, height: 640)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
        .onAppear {
            mii = store.mii(for: accountID) ?? Mii.random()
        }
    }

    // MARK: Retrato

    private var portrait: some View {
        HStack(spacing: Space.lg) {
            MiiView(mii: mii, size: 132)
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Tu Mii")
                    .font(Type.title)
                    .foregroundStyle(Palette.textPrimary)
                Text(Fmt.properName(displayName))
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)

                // Vista previa al tamaño real de uso: un Mii que se ve bien a
                // 132 puntos puede ser una mancha a 22.
                HStack(spacing: Space.sm) {
                    ForEach([34.0, 22.0], id: \.self) { s in
                        MiiView(mii: mii, size: s)
                    }
                    Text("como se va a ver")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                }
                .padding(.top, 4)

                Button {
                    withAnimation(Motion.quick) { mii = Mii.random() }
                } label: {
                    Label("Al azar", systemImage: "dice")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .nativeGlassButton()
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
    }

    // MARK: Pestañas

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Part.allCases) { p in
                    let on = p == tab
                    Button { tab = p } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p.symbol).font(.system(size: 10))
                            Text(p.label).font(Type.caption)
                        }
                        .foregroundStyle(on ? Palette.textOnAccent : Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(on ? prefs.tint
                                                      : Palette.textPrimary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
        }
        .animation(Motion.quick, value: tab)
    }

    // MARK: Opciones

    @ViewBuilder
    private var options: some View {
        switch tab {
        case .cara:
            picker("Forma", count: MiiCatalog.faceCount, names: MiiCatalog.faceNames,
                   selection: $mii.face) { i in var p = mii; p.face = i; return p }
            swatches("Tono de piel", colors: MiiCatalog.skins, selection: $mii.skin)

        case .pelo:
            picker("Estilo", count: MiiCatalog.hairCount, names: MiiCatalog.hairNames,
                   selection: $mii.hair) { i in var p = mii; p.hair = i; return p }
            swatches("Color", colors: MiiCatalog.hairColors, selection: $mii.hairColor)

        case .ojos:
            picker("Forma", count: MiiCatalog.eyeCount, names: MiiCatalog.eyeNames,
                   selection: $mii.eyes) { i in var p = mii; p.eyes = i; return p }
            swatches("Color", colors: MiiCatalog.eyeColors, selection: $mii.eyeColor)
            slider("Separación", value: $mii.eyeSpacing)
            slider("Altura", value: $mii.eyeLevel)

        case .cejas:
            picker("Forma", count: MiiCatalog.browCount, names: MiiCatalog.browNames,
                   selection: $mii.brows) { i in var p = mii; p.brows = i; return p }

        case .nariz:
            picker("Forma", count: MiiCatalog.noseCount, names: MiiCatalog.noseNames,
                   selection: $mii.nose) { i in var p = mii; p.nose = i; return p }

        case .boca:
            picker("Forma", count: MiiCatalog.mouthCount, names: MiiCatalog.mouthNames,
                   selection: $mii.mouth) { i in var p = mii; p.mouth = i; return p }
            slider("Altura", value: $mii.mouthLevel)

        case .barba:
            picker("Estilo", count: MiiCatalog.beardCount, names: MiiCatalog.beardNames,
                   selection: $mii.beard) { i in var p = mii; p.beard = i; return p }

        case .lentes:
            picker("Estilo", count: MiiCatalog.glassesCount, names: MiiCatalog.glassNames,
                   selection: $mii.glasses) { i in var p = mii; p.glasses = i; return p }
            swatches("Color", colors: MiiCatalog.glassColors, selection: $mii.glassColor)

        case .fondo:
            swatches("Color de fondo", colors: MiiCatalog.backgrounds, selection: $mii.background)
        }
    }

    /// Cada opción se dibuja como un Mii completo con esa pieza puesta. Un
    /// listado de nombres ("Almendrados", "Contentos") no dice nada; la cara sí.
    private func picker(_ title: String, count: Int, names: [String],
                        selection: Binding<Int>,
                        preview: @escaping (Int) -> Mii) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).labelCaps()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    let on = selection.wrappedValue == i
                    Button { withAnimation(Motion.quick) { selection.wrappedValue = i } } label: {
                        VStack(spacing: 3) {
                            MiiView(mii: preview(i), size: 52, showBackground: false)
                                .background(Circle().fill(Palette.textPrimary.opacity(0.04)))
                            Text(names[safe: i] ?? "\(i + 1)")
                                .font(Type.micro)
                                .foregroundStyle(on ? Palette.textPrimary : Palette.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(on ? prefs.tint.opacity(0.14) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(on ? prefs.tint.opacity(0.6) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func swatches(_ title: String, colors: [Color],
                          selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).labelCaps()
            HStack(spacing: 7) {
                ForEach(0..<colors.count, id: \.self) { i in
                    let on = selection.wrappedValue == i
                    Button { selection.wrappedValue = i } label: {
                        Circle()
                            .fill(colors[i])
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Palette.textPrimary.opacity(0.15),
                                                           lineWidth: 0.5))
                            .overlay(Circle().strokeBorder(prefs.tint, lineWidth: on ? 2.2 : 0)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
        }
        .padding(.top, Space.xs)
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).labelCaps()
            Slider(value: value, in: 0...1)
                .controlSize(.small)
                .tint(prefs.tint)
        }
        .padding(.top, Space.xs)
    }

    // MARK: Pie

    private var footer: some View {
        HStack(spacing: Space.xs) {
            if store.mii(for: accountID) != nil {
                Button("Quitar Mii", role: .destructive) {
                    store.setMii(nil, for: accountID)
                    dismiss()
                }
                .nativeGlassButton()
                .controlSize(.small)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .nativeGlassButton()
                .controlSize(.small)
            Button("Usar como foto") {
                store.setMii(mii, for: accountID)
                dismiss()
            }
            .nativeGlassButton(prominent: true)
            .tint(prefs.tint)
            .controlSize(.small)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
