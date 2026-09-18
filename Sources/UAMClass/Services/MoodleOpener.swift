import SwiftUI

/// Abre páginas de Moodle en el navegador, con la sesión ya iniciada cuando se
/// puede.
///
/// Sin esto, cada "Abrir en Moodle" te deja en la pantalla de login del sitio,
/// que es exactamente el trabajo que la app existe para ahorrarte.
///
/// El autologin de Moodle es caprichoso a propósito: solo entrega una llave
/// cada seis minutos y exige la misma IP. Por eso acá hay tres capas — llave
/// nueva, la última llave todavía fresca, y en el peor caso la URL pelada. El
/// usuario nunca ve un error: como mucho, ve el login del sitio.
@MainActor
final class MoodleOpener: ObservableObject {
    static let shared = MoodleOpener()

    /// Cuándo pedimos la última llave. Moodle rechaza pedidos seguidos, así que
    /// ni lo intentamos si sabemos que va a fallar.
    private var lastKeyRequest: Date?
    private let cooldown: TimeInterval = 6 * 60

    @Published private(set) var opening = false
    /// Por qué no hubo autologin la última vez. Se muestra una sola vez.
    @Published private(set) var lastNote: String?

    private init() {}

    func open(_ url: URL, state: AppState) {
        Task { await openAsync(url, state: state) }
    }

    /// Atajo para las URLs típicas: `mod/assign/view.php?id=…`
    func open(path: String, state: AppState) {
        Task {
            let base = await state.moodle.baseURL
            guard let url = URL(string: base.absoluteString + path) else { return }
            await openAsync(url, state: state)
        }
    }

    private func openAsync(_ url: URL, state: AppState) async {
        opening = true
        defer { opening = false }

        guard let userID = state.moodleSiteInfo?.userid else {
            PlatformBridge.openURL(url)
            return
        }

        // Si la llave anterior es reciente, Moodle va a rechazar el pedido:
        // se abre directo en vez de gastar una llamada y esperar el error.
        if let last = lastKeyRequest, Date().timeIntervalSince(last) < cooldown {
            lastNote = "Moodle solo entrega una llave de autologin cada 6 minutos. Esta se abre sin sesión."
            PlatformBridge.openURL(url)
            return
        }

        do {
            let authed = try await state.moodle.autologinURL(userId: userID, target: url)
            lastKeyRequest = Date()
            lastNote = nil
            PlatformBridge.openURL(authed)
        } catch {
            lastNote = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
            PlatformBridge.openURL(url)
        }
    }
}
