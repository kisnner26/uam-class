import SwiftUI

/// La vitrina de insignias.
///
/// Moodle ya lleva la cuenta de tus insignias, pero las esconde en una pestaña
/// del perfil que nadie visita. Acá son lo que deberían haber sido siempre: una
/// vitrina de trofeos, con la insignia grande y el día que la ganaste.
struct LogrosView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var badges: [MoodleBadge] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: MoodleBadge?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if loading {
                    loadingGrid
                } else if let error {
                    Card {
                        EmptyState(icon: "rosette",
                                   title: "No se pudieron leer tus insignias",
                                   subtitle: error)
                    }
                } else if badges.isEmpty {
                    Card {
                        EmptyState(icon: "rosette",
                                   title: "Vitrina vacía",
                                   subtitle: "Todavía no ganaste insignias. Aparecen acá en cuanto un docente te otorgue una, o cuando completes una actividad que las emita.")
                    }
                } else {
                    if !siteBadges.isEmpty {
                        section("De la universidad", icon: "building.columns.fill",
                                items: siteBadges)
                    }
                    if !courseBadges.isEmpty {
                        section("De tus materias", icon: "books.vertical.fill",
                                items: courseBadges)
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .sheet(item: $selected) { badge in
            BadgeSheet(badge: badge).environmentObject(prefs).environmentObject(state)
        }
    }

    private var header: some View {
        SectionHeader(
            title: "Logros",
            eyebrow: "Vitrina",
            subtitle: loading ? "Buscando insignias…"
                              : "\(badges.count) insignia\(badges.count == 1 ? "" : "s") ganada\(badges.count == 1 ? "" : "s")",
            trailing: AnyView(
                Button { Task { await load() } } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .nativeGlassButton()
                .controlSize(.small)
                .disabled(loading)
            )
        )
    }

    private var siteBadges: [MoodleBadge] { badges.filter(\.isSiteWide) }
    private var courseBadges: [MoodleBadge] { badges.filter { !$0.isSiteWide } }

    private func section(_ title: String, icon: String,
                         items: [MoodleBadge]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            BlockHeader(icon: icon, title: title, count: items.count) { EmptyView() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.sm)],
                      spacing: Space.sm) {
                ForEach(items, id: \.identity) { badge in
                    BadgeTile(badge: badge) { selected = badge }
                }
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.sm)],
                  spacing: Space.sm) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.surface)
                    .frame(height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
            }
        }
        .redacted(reason: .placeholder)
    }

    private func load() async {
        guard let uid = state.moodleSiteInfo?.userid else { return }
        loading = true
        defer { loading = false }
        do {
            badges = try await state.moodle.userBadges(userId: uid)
            error = nil
        } catch {
            // Es un plugin que se puede desactivar: si el sitio lo apagó, la
            // llamada falla y hay que decirlo, no mostrar una vitrina vacía.
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
            badges = []
        }
    }
}

// MARK: - Mosaico de insignia

private struct BadgeTile: View {
    let badge: MoodleBadge
    let onOpen: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: Space.xs) {
                ZStack {
                    // Halo dorado detrás: una insignia sin brillo es una
                    // calcomanía.
                    Circle()
                        .fill(RadialGradient(
                            colors: [Palette.warning.opacity(hovered ? 0.45 : 0.25), .clear],
                            center: .center, startRadius: 8, endRadius: 58))
                        .frame(width: 116, height: 116)

                    RemoteImage(url: badge.badgeurl) {
                        Image(systemName: "rosette")
                            .font(.system(size: 40))
                            .foregroundStyle(Palette.warning)
                    }
                    .frame(width: 76, height: 76)
                }
                .frame(height: 104)
                .saturation(badge.expired ? 0 : 1)
                .opacity(badge.expired ? 0.55 : 1)

                Text(badge.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)

                if let d = badge.issued {
                    Text(d.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textQuaternary)
                }
                if badge.expired {
                    Pill(text: "Vencida", tone: .neutral, compact: true)
                }
            }
            .padding(.vertical, Space.sm)
            .padding(.horizontal, Space.xs)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Palette.surface))
            .background(shape.fill(Palette.specular).opacity(0.5))
            .overlay(shape.strokeBorder(hovered ? Palette.warning.opacity(0.55)
                                                : Palette.border,
                                        lineWidth: hovered ? 1.6 : 1))
            .shadow(color: Palette.warning.opacity(hovered ? 0.28 : 0.08),
                    radius: hovered ? 18 : 6, y: hovered ? 8 : 2)
            .scaleEffect(hovered ? 1.035 : 1)
            .offset(y: hovered ? -3 : 0)
            .animation(Motion.spring, value: hovered)
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
    }
}

// MARK: - Ficha

private struct BadgeSheet: View {
    let badge: MoodleBadge

    @EnvironmentObject private var prefs: UserPrefs
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Space.md) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.warning.opacity(0.35), .clear],
                                         center: .center, startRadius: 10, endRadius: 90))
                    .frame(width: 180, height: 180)
                RemoteImage(url: badge.badgeurl) {
                    Image(systemName: "rosette")
                        .font(.system(size: 64))
                        .foregroundStyle(Palette.warning)
                }
                .frame(width: 120, height: 120)
            }
            .padding(.top, Space.md)

            Text(badge.name)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)

            if let issuer = badge.issuername, !issuer.isEmpty {
                Text("Otorgada por \(issuer)")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            if !badge.cleanDescription.isEmpty {
                Text(badge.cleanDescription)
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.lg)
            }

            if let d = badge.issued {
                Pill(text: d.formatted(.dateTime.day().month(.wide).year()),
                     icon: "calendar", tone: .neutral)
            }

            Spacer(minLength: 0)

            HStack(spacing: Space.xs) {
                if let hash = badge.uniquehash, !hash.isEmpty {
                    Button {
                        MoodleOpener.shared.open(path: "badges/badge.php?hash=\(hash)",
                                                 state: state)
                    } label: {
                        Label("Ver en Moodle", systemImage: "safari")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                }
                Spacer()
                Button("Cerrar") { dismiss() }
                    .nativeGlassButton(prominent: true)
                    .tint(prefs.tint)
                    .controlSize(.small)
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.md)
        }
        .frame(width: 420, height: 520)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
    }
}
