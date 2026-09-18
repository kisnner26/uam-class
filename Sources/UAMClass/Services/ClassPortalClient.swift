import Foundation

/// Cliente del portal CLASS (ASP.NET PageMethods). Reutiliza el conocimiento
/// del cliente TS: replica el payload byte-a-byte del JS original y detecta
/// el patrón `0_N_…` como "portal bloqueado" en vez de "creds malas".
actor ClassPortalClient {

    struct APIError: Error, LocalizedError {
        let message: String
        let raw: String?
        var errorDescription: String? { message }
    }

    struct LoginResult {
        let status: ClassPortalStatus
        let arreglo: [String]
        let rawD: String
    }

    let baseURL: URL
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(baseURL: URL = AppConfig.classPortalBaseURL) {
        self.baseURL = baseURL

        // Cookie storage privado para este client (no lo comparte con Safari)
        let storage = HTTPCookieStorage()
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = storage
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 25
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"
        ]
        self.cookieStorage = storage
        self.session = URLSession(configuration: cfg)
    }

    // Warm-up para recibir ASP.NET_SessionId
    func warmUp() async throws {
        let url = baseURL.appendingPathComponent("inicioEstudiantes.aspx")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        _ = try await session.data(for: req)
    }

    func login(cif: String, pin: String) async throws -> LoginResult {
        try await warmUp()

        let url = baseURL.appendingPathComponent(
            "estudiantes/Ajax/Ajax_WebMethods.aspx/Rutina_LoginValidezToken"
        )

        // Body idéntico al del JS jQuery: `{ "uCun": "…", "uPsw": "…" }` con espacios.
        let bodyString = "{ \"uCun\": \(escaped(cif)), \"uPsw\": \(escaped(pin)) }"
        let bodyData = bodyString.data(using: .utf8)!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                     forHTTPHeaderField: "Origin")
        req.setValue(baseURL.appendingPathComponent("inicioEstudiantes.aspx").absoluteString,
                     forHTTPHeaderField: "Referer")
        req.httpBody = bodyData

        let (data, _) = try await session.data(for: req)

        let wrapper = try JSONDecoder().decode(AjaxD<String>.self, from: data)
        let rawD = wrapper.d
        let arr = rawD.split(separator: "_", omittingEmptySubsequences: false).map(String.init)

        let code = arr.indices.contains(0) ? arr[0] : ""
        let flag = arr.indices.contains(1) ? arr[1] : ""

        let status: ClassPortalStatus
        switch (code, flag) {
        case ("0", "N"):              status = .portalLocked
        case ("0", _):                status = .badCredentials
        case ("-1", _):               status = .adFailed(flag)
        case ("3", let f) where f != "E": status = .wrongPortal
        case ("1", _), ("3", _), ("4", _): status = .ok
        default:                      status = .unknown(rawD)
        }

        return LoginResult(status: status, arreglo: arr, rawD: rawD)
    }

    private func escaped(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
        // Tomamos el interior del array serializado: ["valor"] -> "valor"
        let text = String(data: data, encoding: .utf8) ?? "[]"
        return String(text.dropFirst().dropLast()) // saca [ y ]
    }
}
