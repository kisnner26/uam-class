import Foundation

/// Cliente Moodle Web Services. Todo pasa por `webservice/rest/server.php`
/// menos el login, que va a `login/token.php`.
actor MoodleClient {

    struct APIError: Error, LocalizedError {
        let message: String
        let errorcode: String?
        var errorDescription: String? { message }
    }

    private(set) var baseURL: URL
    let service: String
    private var token: String?
    /// Token privado que devuelve `login/token.php`. NO sirve para llamar a la
    /// API: su único uso es pedir una llave de autologin (ver `autologinURL`).
    private var privateToken: String?
    private let session: URLSession
    private var lastRequestAt: Date? = nil

    init(baseURL: URL = AppConfig.moodleBaseURL,
         service: String = AppConfig.moodleService,
         token: String? = nil) {
        self.baseURL = baseURL
        self.service = service
        self.token = token

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "UAMClass/1.0 (macOS; Swift)"
        ]
        self.session = URLSession(configuration: cfg)
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func setBaseURL(_ url: URL) {
        self.baseURL = url
    }

    var currentToken: String? { token }
    var currentPrivateToken: String? { privateToken }

    func setPrivateToken(_ t: String?) { privateToken = t }

    // MARK: - Login (token)

    /// Intercambia CIF + PIN por un token de larga vida.
    func fetchToken(cif: String, pin: String) async throws -> String {
        var comps = URLComponents(url: baseURL.appendingPathComponent("login/token.php"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "username", value: cif),
            .init(name: "password", value: pin),
            .init(name: "service",  value: service)
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"

        await pace()
        let (data, response) = try await session.data(for: req)
        try ensureJSON(response: response, data: data,
                       hint: "Endpoint de login (\(baseURL.absoluteString))")

        let resp: MoodleTokenResponse
        do {
            resp = try JSONDecoder().decode(MoodleTokenResponse.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            throw APIError(message: "Moodle respondió algo raro:\n\(preview)",
                           errorcode: nil)
        }

        if let t = resp.token, !t.isEmpty {
            self.token = t
            self.privateToken = resp.privatetoken
            return t
        }
        throw APIError(message: resp.error ?? "Moodle no devolvió token.",
                       errorcode: resp.errorcode)
    }

    /// Verifica que la respuesta sea JSON. Si es HTML/otro, tira un mensaje útil.
    private func ensureJSON(response: URLResponse, data: Data, hint: String) throws {
        if let http = response as? HTTPURLResponse {
            if http.statusCode >= 500 {
                throw APIError(message: "\(hint) devolvió HTTP \(http.statusCode). El servidor Moodle no está disponible en este momento.",
                               errorcode: "http_\(http.statusCode)")
            }
            if http.statusCode == 404 {
                throw APIError(message: "\(hint) devolvió HTTP 404. Verifica que la URL de Moodle sea correcta.",
                               errorcode: "http_404")
            }
        }
        let head = String(data: data.prefix(80), encoding: .utf8) ?? ""
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            throw APIError(message: "El servidor devolvió HTML en vez de JSON — la URL de Moodle probablemente esté mal o el sitio caído. Preview: \(trimmed.prefix(120))",
                           errorcode: "not_json")
        }
    }

    // MARK: - Generic REST call

    func rest<T: Decodable>(_ function: String,
                            params: [String: String] = [:],
                            as type: T.Type) async throws -> T {
        guard let token else {
            throw APIError(message: "Sin token de Moodle. Inicia sesión primero.", errorcode: nil)
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent("webservice/rest/server.php"),
                                  resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "wstoken",           value: token),
            .init(name: "wsfunction",        value: function),
            .init(name: "moodlewsrestformat", value: "json")
        ]
        for (k, v) in params { items.append(.init(name: k, value: v)) }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"

        return try await send(req, function: function, as: type)
    }

    /// Igual que `rest`, pero manda los parámetros en el cuerpo como
    /// `application/x-www-form-urlencoded`.
    ///
    /// Obligatorio para cuestionarios: una respuesta de ensayo o un intento con
    /// muchas preguntas desborda fácil el límite práctico de largo de URL, y el
    /// servidor devuelve 414 o trunca en silencio — que en un examen significa
    /// perder respuestas.
    func restForm<T: Decodable>(_ function: String,
                                params: [String: String] = [:],
                                as type: T.Type) async throws -> T {
        guard let token else {
            throw APIError(message: "Sin token de Moodle. Inicia sesión primero.", errorcode: nil)
        }
        let url = baseURL.appendingPathComponent("webservice/rest/server.php")

        var fields: [String: String] = params
        fields["wstoken"] = token
        fields["wsfunction"] = function
        fields["moodlewsrestformat"] = "json"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(fields)

        return try await send(req, function: function, as: type)
    }

    /// Codificación de formulario. `URLComponents` no sirve acá porque no
    /// escapa `+` ni `&` dentro de los valores, y las respuestas de examen los
    /// contienen a menudo (fórmulas, texto libre).
    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func send<T: Decodable>(_ req: URLRequest,
                                    function: String,
                                    as type: T.Type) async throws -> T {
        await pace()
        let (data, _) = try await session.data(for: req)

        // Moodle a veces devuelve un objeto de error con { exception, errorcode, message }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let exception = obj["exception"] as? String {
            let msg = obj["message"] as? String ?? exception
            let code = obj["errorcode"] as? String
            throw APIError(message: msg, errorcode: code)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
            throw APIError(message: "Respuesta inesperada al decodificar \(function): \(preview)",
                           errorcode: nil)
        }
    }

    // MARK: - Funciones concretas

    func siteInfo() async throws -> MoodleSiteInfo {
        try await rest("core_webservice_get_site_info", as: MoodleSiteInfo.self)
    }

    func courses(userId: Int) async throws -> [MoodleCourse] {
        try await rest("core_enrol_get_users_courses",
                       params: ["userid": String(userId)],
                       as: [MoodleCourse].self)
    }

    func assignments(courseIds: [Int]) async throws -> MoodleAssignmentsResponse {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() {
            params["courseids[\(i)]"] = String(id)
        }
        // `includenotenrolledcourses` no hace falta, pero los adjuntos del
        // enunciado SÍ: sin ellos no se puede resolver una tarea que dice
        // "seguí la rúbrica adjunta".
        return try await rest("mod_assign_get_assignments",
                              params: params,
                              as: MoodleAssignmentsResponse.self)
    }

    func gradeItems(courseId: Int, userId: Int) async throws -> MoodleGradesResponse {
        try await rest("gradereport_user_get_grade_items",
                       params: [
                           "courseid": String(courseId),
                           "userid":   String(userId)
                       ],
                       as: MoodleGradesResponse.self)
    }

    /// Trae las secciones + módulos (recursos, tareas, foros, etc.) de un curso.
    /// Pedimos `includestealthmodules=1` para asegurarnos de traer módulos ocultos
    /// que igual son accesibles.
    func courseContents(courseId: Int) async throws -> [MoodleCourseSection] {
        try await rest("core_course_get_contents",
                       params: [
                           "courseid": String(courseId),
                           "options[0][name]":  "includestealthmodules",
                           "options[0][value]": "1"
                       ],
                       as: [MoodleCourseSection].self)
    }

    /// Descarga un archivo. Devuelve URL local temporal.
    func downloadFile(fileurl: String) async throws -> URL {
        guard let token else {
            throw APIError(message: "Sin token para descargar.", errorcode: nil)
        }
        var comps = URLComponents(string: fileurl)!
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "token" }
        items.append(URLQueryItem(name: "token", value: token))
        comps.queryItems = items

        await pace()
        let (localURL, _) = try await session.download(from: comps.url!)
        return localURL
    }

    /// URL con token para preview/streaming (imágenes, video).
    func tokenizedURL(from fileurl: String) -> URL? {
        guard let token else { return URL(string: fileurl) }
        guard var comps = URLComponents(string: fileurl) else { return nil }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "token" }
        items.append(URLQueryItem(name: "token", value: token))
        comps.queryItems = items
        return comps.url
    }

    // MARK: - Subida de archivos

    /// Sube un archivo al área de borradores del usuario y devuelve su `itemid`.
    ///
    /// No va por `webservice/rest/server.php` sino por `webservice/upload.php`,
    /// que es el único endpoint de Moodle que acepta multipart. El `itemid` que
    /// devuelve es lo que después se le pasa a `mod_assign_save_submission`:
    /// primero el archivo queda en un borrador tuyo, y recién el segundo paso lo
    /// convierte en entrega.
    /// - Parameter itemId: `0` abre un área de borrador nueva. Pasando el
    ///   itemid devuelto por una subida anterior, el archivo se agrega a ESA
    ///   misma área. Es imprescindible para entregas de varios archivos:
    ///   `mod_assign_save_submission` no suma archivos, REEMPLAZA la entrega
    ///   con el área que se le pase — subir de a uno dejaba solo el último.
    func uploadDraft(fileURL: URL, itemId: Int = 0) async throws -> Int {
        guard let token else {
            throw APIError(message: "Sin token de Moodle. Inicia sesión primero.", errorcode: nil)
        }
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        var comps = URLComponents(url: baseURL.appendingPathComponent("webservice/upload.php"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "token", value: token),
            .init(name: "filearea", value: "draft"),
            .init(name: "itemid", value: String(itemId))
        ]

        let boundary = "UAMClass-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                        .data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        await pace()
        let (respData, response) = try await session.data(for: req)
        try ensureJSON(response: response, data: respData, hint: "Subida de archivos")

        // Éxito → array de archivos. Error → objeto con `error`.
        if let uploaded = try? JSONDecoder().decode([MoodleUploadedFile].self, from: respData),
           let first = uploaded.first {
            return first.itemid
        }
        if let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
           let msg = obj["error"] as? String {
            throw APIError(message: msg, errorcode: obj["errorcode"] as? String)
        }
        throw APIError(message: "Moodle no devolvió el identificador del archivo subido.",
                       errorcode: nil)
    }

    // MARK: - Enrolled users (profesores + compañeros)

    func enrolledUsers(courseId: Int) async throws -> [MoodleEnrolledUser] {
        // `userfields` hay que pedirlo explícitamente: por defecto Moodle NO
        // manda username/idnumber/department, y sin eso no se puede buscar por
        // CIF. Si el sitio no expone la identidad, simplemente llegan vacíos.
        let fields = "id,fullname,firstname,lastname,email,username,idnumber,"
                   + "department,institution,lastaccess,roles,groups,"
                   + "profileimageurl,profileimageurlsmall,city,country"
        return try await rest("core_enrol_get_enrolled_users",
                              params: [
                                  "courseid": String(courseId),
                                  "options[0][name]":  "userfields",
                                  "options[0][value]": fields
                              ],
                              as: [MoodleEnrolledUser].self)
    }

    /// Perfil completo de un usuario en el contexto de un curso.
    /// Es la vía que más datos devuelve sobre otra persona (departamento,
    /// roles, grupos y, si el sitio lo permite, sus cursos matriculados).
    func courseUserProfiles(userId: Int, courseId: Int) async throws -> [MoodleUserProfile] {
        try await rest("core_user_get_course_user_profiles",
                       params: [
                           "userlist[0][userid]":   String(userId),
                           "userlist[0][courseid]": String(courseId)
                       ],
                       as: [MoodleUserProfile].self)
    }

    /// Cursos de OTRO usuario. Suele estar restringido salvo que tengas permiso;
    /// si falla, la app cae a "materias en común", que siempre se puede calcular.
    func coursesOf(userId: Int) async throws -> [MoodleCourse] {
        try await rest("core_enrol_get_users_courses",
                       params: ["userid": String(userId)],
                       as: [MoodleCourse].self)
    }

    // MARK: - Foros

    func forumsByCourse(courseId: Int) async throws -> [MoodleForum] {
        try await rest("mod_forum_get_forums_by_courses",
                       params: ["courseids[0]": String(courseId)],
                       as: [MoodleForum].self)
    }

    func discussions(forumId: Int, page: Int = 0, perpage: Int = 20) async throws -> MoodleDiscussionsResponse {
        try await rest("mod_forum_get_forum_discussions_paginated",
                       params: [
                           "forumid": String(forumId),
                           "page": String(page),
                           "perpage": String(perpage)
                       ],
                       as: MoodleDiscussionsResponse.self)
    }

    func posts(discussionId: Int) async throws -> MoodleForumPostsResponse {
        try await rest("mod_forum_get_discussion_posts",
                       params: ["discussionid": String(discussionId)],
                       as: MoodleForumPostsResponse.self)
    }

    /// Agrega un post/reply. Devuelve el id del nuevo post.
    func addForumPost(postId: Int, subject: String, message: String) async throws -> Int {
        struct Reply: Decodable { let postid: Int? }
        let r: Reply = try await rest("mod_forum_add_discussion_post",
                                      params: [
                                          "postid": String(postId),
                                          "subject": subject,
                                          "message": message,
                                          "messageformat": "1"
                                      ],
                                      as: Reply.self)
        return r.postid ?? 0
    }

    // MARK: - Assignment submission status

    func submissionStatus(assignId: Int) async throws -> MoodleAssignSubmissionStatus {
        try await rest("mod_assign_get_submission_status",
                       params: ["assignid": String(assignId)],
                       as: MoodleAssignSubmissionStatus.self)
    }

    // MARK: - Mensajería

    func conversations(userId: Int, type: Int? = nil, favouritesOnly: Bool = false,
                       limitFrom: Int = 0, limitNum: Int = 50) async throws -> [MoodleConversation] {
        var params: [String: String] = [
            "userid": String(userId),
            "limitfrom": String(limitFrom),
            "limitnum": String(limitNum),
            "favourites": favouritesOnly ? "1" : "0"
        ]
        if let type = type { params["type"] = String(type) }
        let resp: MoodleConversationsResponse = try await rest(
            "core_message_get_conversations",
            params: params,
            as: MoodleConversationsResponse.self
        )
        return resp.conversations
    }

    func conversationMessages(currentUserId: Int, convId: Int,
                              limitFrom: Int = 0, limitNum: Int = 100,
                              newest: Bool = true) async throws -> MoodleMessagesResponse {
        try await rest("core_message_get_conversation_messages",
                       params: [
                           "currentuserid":  String(currentUserId),
                           "convid":         String(convId),
                           "limitfrom":      String(limitFrom),
                           "limitnum":       String(limitNum),
                           "newest":         newest ? "1" : "0"
                       ],
                       as: MoodleMessagesResponse.self)
    }

    /// Envía un mensaje a una conversación existente.
    func sendMessage(convId: Int, text: String) async throws -> [MoodleMessage] {
        try await rest("core_message_send_messages_to_conversation",
                       params: [
                           "conversationid": String(convId),
                           "messages[0][text]":         text,
                           "messages[0][textformat]":   "1"
                       ],
                       as: [MoodleMessage].self)
    }

    /// Busca usuarios (contactos + no contactos) por nombre.
    func searchUsers(currentUserId: Int, search: String, limit: Int = 20) async throws -> MoodleUserSearchResponse {
        try await rest("core_message_search_users",
                       params: [
                           "userid": String(currentUserId),
                           "search": search,
                           "limitnum": String(limit)
                       ],
                       as: MoodleUserSearchResponse.self)
    }

    /// Busca por CIF exacto. `core_message_search_users` indexa el nombre
    /// visible, no el username, así que un CIF no cae ahí: hay que preguntar por
    /// campo. Devuelve vacío si el sitio restringe la visibilidad de usuarios.
    func usersByField(_ field: String, values: [String]) async throws -> [MoodleDirectoryUser] {
        var params: [String: String] = ["field": field]
        for (i, v) in values.enumerated() {
            params["values[\(i)]"] = v
        }
        return try await rest("core_user_get_users_by_field",
                              params: params,
                              as: [MoodleDirectoryUser].self)
    }

    /// Consulta abierta al padrón de usuarios. `core_user_get_users` acepta
    /// comodines `%` en nombre/apellido/correo, así que es la única vía para
    /// encontrar a alguien por nombre sin compartir cursos ni saber su CIF.
    ///
    /// Suele exigir `moodle/user:viewdetails` a nivel de sitio, o sea que para
    /// una cuenta de estudiante lo normal es que responda con excepción. Por eso
    /// se usa como último recurso y el que llama debe tolerar el fallo.
    func usersMatching(_ criteria: [(key: String, value: String)],
                       limit: Int = 30) async throws -> [MoodleDirectoryUser] {
        var params: [String: String] = [:]
        for (i, c) in criteria.enumerated() {
            params["criteria[\(i)][key]"]   = c.key
            params["criteria[\(i)][value]"] = c.value
        }
        let resp: MoodleUsersQueryResponse = try await rest(
            "core_user_get_users", params: params, as: MoodleUsersQueryResponse.self)
        return Array(resp.users.prefix(limit))
    }

    // MARK: - Bloques

    /// Bloques de la portada del sitio, con su HTML ya renderizado.
    ///
    /// Interesa uno solo: "Usuarios en línea". Es la única vista que Moodle le
    /// da a un estudiante con gente de TODA la universidad, sin importar cursos
    /// ni carrera — justamente lo que las búsquedas por web service niegan.
    func siteBlocks(returnContents: Bool = true) async throws -> [MoodleBlock] {
        let resp: MoodleBlocksResponse = try await rest(
            "core_block_get_course_blocks",
            params: ["courseid": "1", "returncontents": returnContents ? "1" : "0"],
            as: MoodleBlocksResponse.self)
        return resp.blocks
    }

    /// Lo mismo pero del Área personal, por si el bloque vive ahí y no en la portada.
    func dashboardBlocks(userId: Int, returnContents: Bool = true) async throws -> [MoodleBlock] {
        let resp: MoodleBlocksResponse = try await rest(
            "core_block_get_dashboard_blocks",
            params: ["userid": String(userId),
                     "returncontents": returnContents ? "1" : "0"],
            as: MoodleBlocksResponse.self)
        return resp.blocks
    }

    /// Devuelve el id de la conversación 1-a-1 con otro usuario (creándola si no existe
    /// implícitamente al enviarle el primer mensaje via `core_message_send_instant_messages`).
    func sendInstantMessage(toUserId: Int, text: String) async throws {
        struct Ack: Decodable {}
        _ = try await rest("core_message_send_instant_messages",
                           params: [
                               "messages[0][touserid]": String(toUserId),
                               "messages[0][text]":     text,
                               "messages[0][textformat]":"1"
                           ],
                           as: [MoodleMessage].self)
    }

    // MARK: - Rate limit

    private func pace() async {
        let intervalNs = UInt64(AppConfig.minRequestIntervalMs) * 1_000_000
        if let last = lastRequestAt {
            let elapsedSec = Date().timeIntervalSince(last)
            if elapsedSec >= 0, elapsedSec < 60 {  // guarda anti-overflow y anti-desfase
                let elapsedNs = UInt64(elapsedSec * 1_000_000_000)
                if elapsedNs < intervalNs {
                    try? await Task.sleep(nanoseconds: intervalNs - elapsedNs)
                }
            }
        }
        lastRequestAt = Date()
    }
}
