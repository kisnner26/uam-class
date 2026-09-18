import SwiftUI

/// Image view que descarga (con token de Moodle) y cachea en disco.
/// Si la URL falla, muestra un placeholder.
struct RemoteImage<Placeholder: View>: View {
    let url: String?
    let placeholder: () -> Placeholder
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?
    @State private var failed = false

    init(url: String?,
         contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url = url, !url.isEmpty else { failed = true; return }

        // Cache primero
        if let cached = OfflineCache.shared.loadImage(for: url) {
            self.image = cached
            return
        }

        // Descarga con token si es un endpoint de Moodle
        do {
            let tokenized = await MoodleClientRegistry.shared.tokenize(url: url)
            guard let requestURL = URL(string: tokenized) else { failed = true; return }
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            if let img = PlatformImage(data: data) {
                OfflineCache.shared.saveImage(data, for: url)
                await MainActor.run { self.image = img }
            }
        } catch {
            await MainActor.run { self.failed = true }
        }
    }
}

/// Registry global para acceder al MoodleClient desde views (para tokenizar URLs).
@MainActor
final class MoodleClientRegistry {
    static let shared = MoodleClientRegistry()
    weak var client: MoodleClient?

    func tokenize(url: String) async -> String {
        guard let client = client else { return url }
        if let tokenized = await client.tokenizedURL(from: url) {
            return tokenized.absoluteString
        }
        return url
    }
}

// MARK: - Avatar

/// La cara de una persona. Prioridad, de mayor a menor:
///
///  1. **Tu Mii**, si sos vos y lo creaste. Es una elección explícita tuya y le
///     gana hasta a tu foto real de Moodle.
///  2. **La foto real** del sitio, si existe de verdad.
///  3. **Un Mii determinístico** derivado de su identidad.
///
/// El punto 3 es lo que hace que TODO el mundo tenga cara, sin que nadie haya
/// creado nada — como el desfile de Miis de la consola. Y como la semilla es su
/// id, la cara nunca cambia: se vuelve reconocible, y dejás de leer nombres para
/// empezar a reconocer gente.
///
/// Antes acá había iniciales. Dos letras grises no son una persona.
struct Avatar: View {
    let url: String?
    let name: String
    var size: CGFloat = 30
    /// Círculo con el color de acento (para docentes o para vos).
    var accent: Bool = false
    /// Id de Moodle, si se conoce. Es la mejor semilla y además permite
    /// reconocer que esta persona sos vos.
    var userID: Int? = nil

    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var localStore = LocalStore.shared
    @ObservedObject private var accounts = AccountStore.shared

    /// Tu Mii, si esta cara es la tuya.
    private var ownMii: Mii? {
        guard let uid = userID,
              let account = accounts.accounts.first(where: { $0.userid == uid })
        else { return nil }
        return localStore.mii(for: account.id)
    }

    /// Las URLs de la silueta por defecto salen del tema, no de los archivos
    /// del usuario: `theme/image.php/.../u/f1`. Las reales van por pluginfile.
    private var realPhoto: String? {
        guard let u = url, !u.isEmpty else { return nil }
        let lower = u.lowercased()
        guard !lower.contains("theme/image.php"), !lower.contains("/core/1/u/") else { return nil }
        return u
    }

    private var fallbackMii: Mii {
        Mii.deterministic(seed: userID.map(String.init) ?? name)
    }

    var body: some View {
        ZStack {
            if let ownMii {
                MiiView(mii: ownMii, size: size)
            } else if realPhoto != nil {
                Circle().fill(prefs.tint.opacity(0.12))
                RemoteImage(url: realPhoto) {
                    MiiView(mii: fallbackMii, size: size)
                }
                .clipShape(Circle())
            } else {
                MiiView(mii: fallbackMii, size: size)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(accent ? prefs.tint.opacity(0.85)
                                              : Palette.textPrimary.opacity(0.10),
                                       lineWidth: accent ? 1.6 : 0.5))
    }
}
