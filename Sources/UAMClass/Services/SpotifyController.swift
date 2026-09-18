import SwiftUI
import AppKit

// MARK: - Spotify
//
// Controla la app de Spotify que ya está instalada en la Mac, por Apple Events.
// No hay OAuth, ni Client ID, ni servidor: por eso funciona apenas se abre y no
// pide contraseña de nada.
//
// La contracara es el alcance. Apple Events deja LEER lo que suena y mandar
// play/pausa/siguiente, pero no deja buscar ni listar tus playlists — para eso
// haría falta la Web API con cuenta vinculada (y Premium para reproducir).
// Elegimos esto porque un reproductor que funciona hoy vale más que uno completo
// que exige registrar una app de desarrollador.
//
// macOS pide permiso de Automatización la primera vez. Si lo negás, el error
// -1743 vuelve para siempre hasta que se cambie a mano en Configuración: por eso
// se detecta y se ofrece el atajo en vez de fallar en silencio.

@MainActor
final class SpotifyController: ObservableObject {
    static let shared = SpotifyController()

    struct Track: Equatable {
        var name: String
        var artist: String
        var album: String
        var artworkURL: String?
        var durationSeconds: Double
    }

    @Published private(set) var installed = false
    @Published private(set) var running = false
    @Published private(set) var isPlaying = false
    @Published private(set) var track: Track?
    @Published private(set) var position: Double = 0
    /// El usuario negó el permiso de Automatización. No se arregla reintentando.
    @Published private(set) var permissionDenied = false

    private var timer: Timer?
    private var watchers = 0

    private let bundleID = "com.spotify.client"

    private init() {
        installed = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    // MARK: Ciclo de vida
    //
    // Se sondea solo mientras algo lo está mirando. Un timer eterno para leer una
    // canción que nadie ve es gasto de batería.

    func beginWatching() {
        watchers += 1
        guard timer == nil else { return }
        refresh()
        // Cada segundo, para que el contador de tiempo avance parejo. Es un
        // Apple Event local: cuesta menos que redibujar la ventana.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    // MARK: Lectura

    func refresh() {
        installed = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) != nil

        // Se pregunta por NSWorkspace y no por AppleScript a propósito: mandarle
        // un evento a Spotify cerrado LO ABRE, y abrir Spotify porque sí, al
        // entrar a ver las notas, sería una grosería.
        running = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleID }

        guard running else {
            isPlaying = false
            track = nil
            position = 0
            return
        }

        guard let raw = run(script: Self.stateScript) else { return }
        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count >= 7 else { return }

        isPlaying = parts[0] == "playing"
        position = Double(parts[6]) ?? 0

        let name = parts[1]
        if name.isEmpty {
            track = nil
        } else {
            track = Track(name: name,
                          artist: parts[2],
                          album: parts[3],
                          artworkURL: parts[4].isEmpty ? nil : parts[4],
                          // Spotify devuelve la duración en milisegundos.
                          durationSeconds: (Double(parts[5]) ?? 0) / 1000)
        }
    }

    // MARK: Control

    func playPause() { command("playpause") }

    /// Salta a un punto de la canción, en segundos.
    func seek(to seconds: Double) {
        guard running else { return }
        let target = max(0, seconds)
        position = target                     // respuesta inmediata en pantalla
        _ = run(script: "tell application \"Spotify\" to set player position to \(target)")
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.refresh()
        }
    }
    func next()      { command("next track") }
    func previous()  { command("previous track") }

    /// Abre Spotify. Solo se llama desde un botón explícito.
    func launch() {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration())
        // Darle un respiro antes de preguntarle nada.
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.refresh()
        }
    }

    /// Lleva a Configuración → Privacidad → Automatización, que es el único
    /// lugar donde se revierte un permiso negado.
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func command(_ verb: String) {
        guard running else { return }
        _ = run(script: "tell application \"Spotify\" to \(verb)")
        // La app tarda un instante en reflejar el cambio.
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.refresh()
        }
    }

    // MARK: AppleScript

    /// Un solo evento devuelve todo el estado, separado por US (0x1F) — un
    /// carácter que no puede aparecer en el nombre de una canción.
    ///
    /// Dos cosas que costaron caro y no hay que volver a romper:
    ///
    ///  · Los nombres de variable NO pueden ser abreviaturas cortas. `st` hace
    ///    que AppleScript falle en el parseo con "Expected expression" — choca
    ///    con la terminología del diccionario. Todo va con prefijo `the`.
    ///  · Cada propiedad tiene su propio `try`. Con un solo `try` envolviendo
    ///    todo, una sola propiedad ausente (un archivo local sin portada, por
    ///    ejemplo) dejaba título, artista y álbum vacíos: la canción entera
    ///    desaparecía por culpa de la carátula.
    private static let stateScript = """
    tell application "Spotify"
        set theState to (player state as text)
        set theName to ""
        set theArtist to ""
        set theAlbum to ""
        set theArt to ""
        set theDuration to 0
        set thePosition to 0
        try
            set theName to name of current track
        end try
        try
            set theArtist to artist of current track
        end try
        try
            set theAlbum to album of current track
        end try
        try
            set theArt to artwork url of current track
        end try
        try
            set theDuration to duration of current track
        end try
        try
            set thePosition to player position
        end try
        return theState & (ASCII character 31) & theName & (ASCII character 31) & theArtist & (ASCII character 31) & theAlbum & (ASCII character 31) & theArt & (ASCII character 31) & theDuration & (ASCII character 31) & thePosition
    end tell
    """

    @discardableResult
    private func run(script source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: el usuario negó Automatización. -600: la app no corre.
            if code == -1743 { permissionDenied = true }
            if code == -600 { running = false }
            return nil
        }

        permissionDenied = false
        return result.stringValue
    }
}
