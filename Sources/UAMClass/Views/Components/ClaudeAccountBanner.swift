import SwiftUI

/// Estado de la sesión de Claude, con el botón para volver a entrar.
///
/// Va arriba de todo lo que usa Claude (Estudiar, Resolver tarea, Configuración)
/// para que una sesión vencida se vea ANTES de apretar un botón y esperar un
/// minuto a que falle.
struct ClaudeAccountBanner: View {
    /// Compacto: una sola línea, para meterlo dentro de otros paneles.
    var compact: Bool = false

    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var auth = ClaudeAuth.shared

    var body: some View {
        Group {
            switch auth.state {
            case .loggedIn(let detail):
                // Conectado no merece un cartel grande: una línea discreta.
                if !compact {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.success).frame(width: 7, height: 7)
                        Text("Claude conectado\(detail.map { " · \($0)" } ?? "")")
                            .font(Type.micro)
                            .foregroundStyle(Palette.textTertiary)
                        Spacer(minLength: 0)
                        Button { auth.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textQuaternary)
                        .help("Volver a comprobar")
                    }
                }

            case .unknown, .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Comprobando la sesión de Claude…")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                    Spacer(minLength: 0)
                }

            case .notInstalled:
                card(icon: "exclamationmark.triangle.fill", tone: Palette.warning,
                     title: "Claude Code no está instalado",
                     detail: "Instalalo con `brew install claude` y reabrí la app.") {
                    EmptyView()
                }

            case .loggedOut:
                card(icon: "person.crop.circle.badge.exclamationmark", tone: Palette.warning,
                     title: "La sesión de Claude venció",
                     detail: "Sin sesión no se pueden resolver tareas ni estudiar con el material. Se abre Terminal, autorizás en el navegador y listo.") {
                    Button { auth.login() } label: {
                        Label("Iniciar sesión", systemImage: "person.badge.key")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .nativeGlassButton(prominent: true)
                    .tint(prefs.tint)
                    .controlSize(.small)
                }

            case .waitingForLogin:
                card(icon: "hourglass", tone: prefs.tint,
                     title: "Esperando que autorices en el navegador…",
                     detail: "Completá el inicio de sesión en la ventana de Terminal. La app se da cuenta sola cuando terminás.") {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Button("Cancelar") { auth.cancelWaiting() }
                            .nativeGlassButton()
                            .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            if auth.state == .unknown { auth.refresh() }
        }
    }

    private func card<Trailing: View>(icon: String, tone: Color, title: String,
                                      detail: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                if !compact {
                    Text(.init(detail))
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(tone.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(tone.opacity(0.25), lineWidth: 1))
    }
}
