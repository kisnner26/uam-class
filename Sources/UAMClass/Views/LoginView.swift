import SwiftUI

struct LoginView: View {
    let platform: Platform
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var cif = ""
    @State private var pin = ""
    @State private var loading = false
    @State private var appeared = false

    private var accent: Color {
        platform == .moodle ? Palette.bay : Palette.accent
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: accent, intensity: 1.1)
            content
        }
        .onAppear {
            withAnimation(Motion.spring.delay(0.05)) { appeared = true }
        }
        .animation(Motion.spring, value: state.lastError)
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            card
                .frame(maxWidth: 430)
                .padding(.horizontal, Space.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button(action: { state.backToPicker() }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Volver")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassChip(interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(Space.lg)
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            heroBanner
            form
        }
        .glassPanel(radius: Radius.lg, elevation: .floating)
    }

    /// Lámina superior: el logotipo real de la UAM sobre el color, con el
    /// mismo brillo diagonal de los mosaicos. Antes acá había un número romano
    /// gigante de relleno y un icono del sistema en una caja cuadrada.
    private var heroBanner: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Marca de agua: el logotipo, grande y apenas visible.
            UAMLogo(height: 150)
                .opacity(0.10)
                .offset(x: 60, y: 10)
                .allowsHitTesting(false)

            LinearGradient(colors: [.white.opacity(0.26), .clear],
                           startPoint: .top, endPoint: .center)

            HStack(spacing: Space.sm) {
                UAMMark(size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.subtitle.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(platform.displayName)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg)
        }
        .frame(height: 128)
        .clipped()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if platform == .moodle {
                instanceSelector
            }

            VStack(spacing: Space.sm) {
                TextInput(label: "CIF", text: $cif,
                          placeholder: "22XXXXXX", icon: "person.text.rectangle")
                TextInput(label: "PIN", text: $pin,
                          placeholder: "••••••", isSecure: true, icon: "key.fill")
            }

            if let err = state.lastError {
                errorBanner(err)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PrimaryButton(
                title: loading ? "Ingresando…" : "Ingresar",
                icon: loading ? nil : "arrow.right",
                loading: loading,
                disabled: cif.isEmpty || pin.isEmpty,
                action: submit
            )
            .keyboardShortcut(.defaultAction)
            .padding(.top, 2)

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .symbolRenderingMode(.hierarchical)
                Text("Tu PIN nunca se guarda en disco.")
                    .font(Type.micro)
                Spacer()
            }
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(Space.lg)
    }

    private var instanceSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instancia").labelCaps()
            HStack(spacing: 6) {
                ForEach(AppConfig.MoodleInstance.allCases) { inst in
                    InstanceChip(
                        label: inst.displayName,
                        selected: state.moodleInstance == inst,
                        tint: accent
                    ) {
                        withAnimation(Motion.quick) { state.moodleInstance = inst }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 1)
            Text(msg)
                .font(Type.caption)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.danger.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.danger.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func submit() {
        guard !cif.isEmpty, !pin.isEmpty else { return }
        loading = true
        Task {
            await state.login(cif: cif, pin: pin, into: platform)
            pin = ""
            loading = false
        }
    }
}

private struct InstanceChip: View {
    let label: String
    let selected: Bool
    let tint: Color
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : Palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule().fill(tint.brandGradient)
                            .shadow(color: tint.opacity(0.4), radius: 6, x: 0, y: 2)
                    } else {
                        Capsule().fill(Palette.textPrimary.opacity(hovered ? 0.09 : 0.05))
                    }
                }
                .overlay(
                    Capsule().strokeBorder(selected ? Palette.rimOnDark
                                                    : LinearGradient(colors: [Palette.border],
                                                                     startPoint: .top,
                                                                     endPoint: .bottom),
                                           lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .animation(Motion.quick, value: selected)
    }
}
