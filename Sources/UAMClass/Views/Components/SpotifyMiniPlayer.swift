import SwiftUI

/// Lo que suena, al pie de la barra lateral.
///
/// Vive acá y no en una sección propia porque la música acompaña al estudio: se
/// quiere ver mientras leés las notas, no en una pantalla aparte a la que hay
/// que ir. Si Spotify no está instalado, no se dibuja nada — un control muerto
/// es peor que ningún control.
struct SpotifyMiniPlayer: View {
    @StateObject private var spotify = SpotifyController.shared
    @EnvironmentObject private var prefs: UserPrefs

    @State private var expanded = false
    @State private var hovered = false
    /// Mientras arrastrás, manda la posición del dedo y no la de Spotify: si no,
    /// el sondeo de cada segundo tironea la barra hacia atrás.
    @State private var scrubbing: Double?

    var body: some View {
        Group {
            if spotify.installed {
                content
            }
        }
        .onAppear { spotify.beginWatching() }
        .onDisappear { spotify.endWatching() }
    }

    @ViewBuilder
    private var content: some View {
        if spotify.permissionDenied {
            deniedRow
        } else if !spotify.running {
            launchRow
        } else {
            nowPlayingRow
        }
    }

    // MARK: Estados previos a poder controlar nada

    private var launchRow: some View {
        Button { spotify.launch() } label: {
            row {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.06)))
                Text("Abrir Spotify")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var deniedRow: some View {
        Button { spotify.openAutomationSettings() } label: {
            row {
                Image(systemName: "lock.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.warning)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Spotify sin permiso")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Activalo en Automatización")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help("Configuración → Privacidad y seguridad → Automatización")
    }

    // MARK: Reproduciendo

    private var nowPlayingRow: some View {
        Button { expanded = true } label: {
            row {
                artwork(size: 26, radius: Radius.sm)

                VStack(alignment: .leading, spacing: 1) {
                    Text(spotify.track?.name ?? "Spotify")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(spotify.track?.artist ?? "Nada sonando")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button { spotify.playPause() } label: {
                    Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(prefs.tint)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $expanded, arrowEdge: .trailing) {
            expandedPlayer
        }
    }

    private var expandedPlayer: some View {
        VStack(spacing: Space.sm) {
            artwork(size: 148, radius: Radius.lg)

            VStack(spacing: 2) {
                Text(spotify.track?.name ?? "Nada sonando")
                    .font(Type.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(spotify.track?.artist ?? "")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                if let album = spotify.track?.album, !album.isEmpty {
                    Text(album)
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                }
            }

            if let t = spotify.track, t.durationSeconds > 0 {
                VStack(spacing: 3) {
                    scrubBar(duration: t.durationSeconds)
                    HStack {
                        Text(Self.clock(scrubbing ?? spotify.position))
                        Spacer()
                        Text(Self.clock(t.durationSeconds))
                    }
                    .font(Type.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textQuaternary)
                }
            }

            HStack(spacing: Space.md) {
                control("backward.fill", size: 13) { spotify.previous() }
                control(spotify.isPlaying ? "pause.fill" : "play.fill",
                        size: 17, prominent: true) { spotify.playPause() }
                control("forward.fill", size: 13) { spotify.next() }
            }
            .padding(.top, 2)

            Text("Controla la app de Spotify de tu Mac")
                .font(Type.micro)
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(Space.md)
        .frame(width: 220)
    }

    /// Barra arrastrable. `minimumDistance: 0` a propósito: un clic simple en
    /// cualquier punto también salta ahí, que es como se comporta cualquier
    /// reproductor y lo que la mano espera.
    private func scrubBar(duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let shown = (scrubbing ?? spotify.position) / duration

            ZStack(alignment: .leading) {
                Capsule().fill(Palette.textPrimary.opacity(0.12))
                Capsule().fill(prefs.tint)
                    .frame(width: w * min(1, max(0, shown)))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        scrubbing = min(duration, max(0, v.location.x / w * duration))
                    }
                    .onEnded { v in
                        let target = min(duration, max(0, v.location.x / w * duration))
                        spotify.seek(to: target)
                        scrubbing = nil
                    }
            )
        }
        .frame(height: 12)
    }

    // MARK: Piezas

    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: Space.xs, content: content)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.textPrimary.opacity(hovered ? 0.05 : 0)))
            .contentShape(Rectangle())
            .consoleHover($hovered)
            .animation(Motion.quick, value: hovered)
    }

    /// La portada la sirve el CDN de Spotify, sin token: va por `AsyncImage` y
    /// no por `RemoteImage`, que le pegaría el token de Moodle a la URL.
    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(Palette.textPrimary.opacity(0.06))
            if let url = spotify.track?.artworkURL, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(Palette.textQuaternary)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private func control(_ symbol: String, size: CGFloat,
                         prominent: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? Palette.textOnAccent : Palette.textPrimary)
                .frame(width: prominent ? 38 : 30, height: prominent ? 38 : 30)
                .background(
                    Circle().fill(prominent ? prefs.tint : Palette.textPrimary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
