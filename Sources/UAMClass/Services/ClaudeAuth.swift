import Foundation
import AppKit

// MARK: - Sesión de Claude
//
// La app usa el CLI `claude` con TU suscripción, y esa sesión puede vencer. Lo
// que pasaba antes: el botón "Resolver" o "Preguntar" se lanzaba igual, el CLI
// fallaba con un error de autenticación enterrado en el registro, y nada en la
// pantalla decía por qué.
//
// Ahora se consulta el estado ANTES (`claude auth status`, instantáneo y sin
// gastar un token) y, si hace falta, se ofrece volver a iniciar sesión.
//
// El login se abre en Terminal y no como subproceso a propósito: el flujo es
// interactivo —abre el navegador, espera la autorización, a veces pide un
// código— y sin una terminal real se queda colgado esperando una respuesta que
// nunca llega. Un archivo `.command` lo abre en Terminal sin necesitar permisos
// de Automatización.

@MainActor
final class ClaudeAuth: ObservableObject {
    static let shared = ClaudeAuth()

    enum State: Equatable {
        case unknown
        case checking
        case notInstalled
        case loggedOut
        case loggedIn(detail: String?)
        case waitingForLogin
    }

    @Published private(set) var state: State = .unknown

    var isReady: Bool {
        if case .loggedIn = state { return true }
        return false
    }

    private var pollTask: Task<Void, Never>?

    private init() {}

    // MARK: Consultar

    func refresh() {
        guard state != .waitingForLogin else { return }
        state = .checking
        Task { state = await Self.probe() }
    }

    /// `claude auth status --json`. No usa la red de Anthropic ni gasta tokens.
    private static func probe() async -> State {
        guard let binary = ClaudeRunner.locate() else { return .notInstalled }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: binary)
                p.arguments = ["auth", "status", "--json"]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                    p.waitUntilExit()
                } catch {
                    cont.resume(returning: .loggedOut)
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    cont.resume(returning: .loggedOut)
                    return
                }
                guard obj["loggedIn"] as? Bool == true else {
                    cont.resume(returning: .loggedOut)
                    return
                }
                // El detalle varía entre versiones del CLI: se muestra lo que haya.
                let detail = (obj["email"] as? String)
                    ?? (obj["subscriptionType"] as? String).map { "plan \($0)" }
                    ?? (obj["authMethod"] as? String)
                cont.resume(returning: .loggedIn(detail: detail))
            }
        }
    }

    // MARK: Iniciar sesión

    /// Abre Terminal con `claude auth login` y espera a que termines.
    func login() {
        guard let binary = ClaudeRunner.locate() else {
            state = .notInstalled
            return
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("UAMClass", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let script = base.appendingPathComponent("iniciar-sesion-claude.command")

        let body = """
        #!/bin/zsh
        clear
        echo "UAM Class — iniciar sesión en Claude"
        echo ""
        echo "Se va a abrir el navegador. Autorizá con tu cuenta de Claude"
        echo "y volvé a la app: se da cuenta sola cuando terminás."
        echo ""
        "\(binary)" auth login --claudeai
        echo ""
        echo "Listo. Podés cerrar esta ventana."
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: script.path)
        } catch {
            state = .loggedOut
            return
        }

        NSWorkspace.shared.open(script)
        state = .waitingForLogin
        startPolling()
    }

    /// Consulta cada 3 segundos hasta que la sesión aparezca, con tope de 10
    /// minutos para no quedar sondeando para siempre si cerraste la ventana.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let s = await Self.probe()
                if case .loggedIn = s {
                    state = s
                    SoundKit.shared.play(.confirm)
                    return
                }
            }
            if state == .waitingForLogin { state = .loggedOut }
        }
    }

    func cancelWaiting() {
        pollTask?.cancel()
        state = .loggedOut
        refresh()
    }

    /// El runner avisa cuando una corrida falló por autenticación, para que la
    /// pantalla lo diga en vez de mostrar un código de salida.
    func markExpired() {
        state = .loggedOut
    }

    static func looksLikeAuthError(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("not logged in") || t.contains("please run /login")
            || t.contains("invalid api key") || t.contains("authentication")
            || t.contains("oauth") || t.contains("401") || t.contains("unauthorized")
    }
}
