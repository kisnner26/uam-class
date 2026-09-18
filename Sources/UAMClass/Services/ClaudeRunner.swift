import Foundation

// MARK: - Puente a Claude Code
//
// Corre el CLI `claude` como subproceso, con tu suscripción. No hay clave de API
// ni servidor de por medio: es el mismo binario que usás en la terminal.
//
// Dos cosas que hacen falta y no son obvias:
//
//  · Una app lanzada desde Finder NO hereda tu PATH. `/opt/homebrew/bin` no
//    existe para ella, así que buscar "claude" a secas falla siempre. Por eso
//    se prueban rutas conocidas y, como último recurso, se le pregunta a un
//    shell de login.
//  · La salida se pide en `stream-json`, que emite una línea por evento. Eso
//    permite mostrar en vivo qué está haciendo — leyendo el enunciado,
//    escribiendo el borrador — en vez de una ruedita de diez minutos.

@MainActor
final class ClaudeRunner: ObservableObject {

    struct Event: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case thinking, tool, output, error }
    }

    @Published private(set) var running = false
    @Published private(set) var events: [Event] = []
    @Published private(set) var finished = false
    @Published private(set) var failure: String?
    /// Lo que costó la corrida, si el CLI lo informa.
    @Published private(set) var costUSD: Double?
    @Published private(set) var durationMs: Int?

    private var process: Process?

    // MARK: Localizar el binario

    static func locate() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.claude/local/claude",
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/bin/claude"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Último recurso: un shell de login sí tiene el PATH del usuario.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
        } catch { }
        return nil
    }

    static var isInstalled: Bool { locate() != nil }

    // MARK: Correr

    func run(prompt: String, in directory: URL) {
        guard !running else { return }
        guard let binary = Self.locate() else {
            failure = "No encontré el comando `claude` en esta Mac. Instalá Claude Code y volvé a intentar."
            return
        }

        events = []
        failure = nil
        finished = false
        costUSD = nil
        durationMs = nil
        running = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.currentDirectoryURL = directory
        task.arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            // Sin esto el CLI pide confirmación por cada escritura y se cuelga
            // esperando una respuesta que en modo headless nunca llega.
            "--permission-mode", "acceptEdits",
            "--allowedTools", "Read,Write,Edit,Glob,Grep,Bash,WebFetch,WebSearch",
            "--add-dir", directory.path
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
                    + (env["PATH"] ?? "")
        task.environment = env

        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(text) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { @MainActor in
                if ClaudeAuth.looksLikeAuthError(text) {
                    ClaudeAuth.shared.markExpired()
                    self?.failure = "La sesión de Claude venció. Iniciá sesión de nuevo y volvé a intentar."
                }
                self?.append(text, kind: .error)
            }
        }

        task.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.running = false
                self?.finished = true
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 && self?.failure == nil {
                    self?.failure = "Claude terminó con código \(proc.terminationStatus). Revisá el registro."
                }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            running = false
            failure = "No se pudo lanzar Claude: \(error.localizedDescription)"
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        running = false
    }

    // MARK: Parseo del stream

    private var buffer = ""

    private func ingest(_ chunk: String) {
        buffer += chunk
        // NDJSON: un objeto por línea. La última puede venir cortada.
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<nl])
            buffer = String(buffer[buffer.index(after: nl)...])
            handle(line: line.trimmingCharacters(in: .whitespaces))
        }
    }

    private func handle(line: String) {
        guard !line.isEmpty, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch obj["type"] as? String {
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let t = (block["text"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                        append(t, kind: .thinking)
                    }
                case "tool_use":
                    let name = block["name"] as? String ?? "herramienta"
                    append(describe(tool: name, input: block["input"] as? [String: Any]),
                           kind: .tool)
                default: break
                }
            }
        case "result":
            if let cost = obj["total_cost_usd"] as? Double { costUSD = cost }
            if let ms = obj["duration_ms"] as? Int { durationMs = ms }
            if obj["is_error"] as? Bool == true {
                let msg = (obj["result"] as? String) ?? "Claude devolvió un error."
                if ClaudeAuth.looksLikeAuthError(msg) {
                    ClaudeAuth.shared.markExpired()
                    failure = "La sesión de Claude venció. Iniciá sesión de nuevo y volvé a intentar."
                } else {
                    failure = msg
                }
            } else if let r = (obj["result"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
                append(r, kind: .output)
            }
        default: break
        }
    }

    /// Traduce el uso de herramientas a algo legible. "Write file.md" dice más
    /// que "tool_use".
    private func describe(tool: String, input: [String: Any]?) -> String {
        let file = (input?["file_path"] as? String).map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        switch tool {
        case "Read":      return "Leyendo \(file ?? "un archivo")"
        case "Write":     return "Escribiendo \(file ?? "el borrador")"
        case "Edit":      return "Corrigiendo \(file ?? "el borrador")"
        case "Bash":      return "Ejecutando un comando"
        case "WebSearch": return "Buscando en la web"
        case "WebFetch":  return "Leyendo una página"
        case "Glob", "Grep": return "Explorando los archivos de la tarea"
        default:          return tool
        }
    }

    private func append(_ text: String, kind: Event.Kind) {
        events.append(Event(text: text, kind: kind))
        // El registro no crece sin límite: interesa lo último.
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }
}
