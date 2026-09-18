import SwiftUI

// MARK: - Pantallas del CLASS Portal
//
// El portal de registro está cerrado fuera del período de matrícula, así que
// estas cuatro secciones comparten un mismo estado de espera. En vez de
// cuatro "sin datos" genéricos, cada una explica qué va a mostrar y de dónde
// lo va a sacar.

/// Pantalla de sección pendiente. Explica el qué y el de dónde, y ofrece
/// abrir el portal real mientras tanto.
struct PortalPlaceholder: View {
    let title: String
    let eyebrow: String
    let subtitle: String
    let icon: String
    let bullets: [String]
    var source: String

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                SectionHeader(title: title, eyebrow: eyebrow, subtitle: subtitle)

                Card(padding: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        HStack(spacing: Space.md) {
                            IconTile(symbol: icon, tint: prefs.tint, size: 46, filled: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Esperando la reapertura del portal")
                                    .font(Type.heading)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("UAM cierra CLASS fuera del período de matrícula. En cuanto vuelva a abrir, esta sección se llena sola.")
                                    .font(Type.caption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }

                        Divider().overlay(Palette.divider)

                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Lo que vas a ver acá").labelCaps()
                            ForEach(bullets, id: \.self) { b in
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(prefs.tint)
                                        .frame(width: 14)
                                    Text(b)
                                        .font(Type.body)
                                        .foregroundStyle(Palette.textSecondary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }

                        HStack(spacing: Space.xs) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 10))
                            Text(source)
                                .font(Type.mono)
                            Spacer(minLength: 0)
                            Button {
                                PlatformBridge.openURL(AppConfig.classPortalBaseURL)
                            } label: {
                                Label("Abrir el portal", systemImage: "safari")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(prefs.tint)
                        }
                        .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }
}

struct PersonalesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        PortalPlaceholder(
            title: "Datos personales",
            eyebrow: "CLASS Portales",
            subtitle: "Tu ficha en el registro académico",
            icon: "person.text.rectangle.fill",
            bullets: [
                "Nombre completo, CIF y carrera",
                "Datos de contacto registrados",
                "Estado de matrícula del período"
            ],
            source: "estudiantes/PersonalesV2.aspx"
        )
    }
}
