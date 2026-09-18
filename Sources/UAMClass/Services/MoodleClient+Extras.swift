import Foundation

// MARK: - Insignias, autologin y encuestas

extension MoodleClient {

    // MARK: Insignias

    /// Las insignias que ganó el usuario. `courseid: 0` = de todo el sitio.
    func userBadges(userId: Int, courseId: Int = 0) async throws -> [MoodleBadge] {
        let resp: MoodleBadgesResponse = try await rest(
            "core_badges_get_user_badges",
            params: ["userid": String(userId), "courseid": String(courseId),
                     "page": "0", "perpage": "100"],
            as: MoodleBadgesResponse.self)
        return resp.badges
    }

    // MARK: Autologin

    /// Devuelve una URL que abre el navegador YA con la sesión iniciada.
    ///
    /// Tres condiciones que hacen que esto falle seguido, y por eso quien llama
    /// tiene que tener siempre un plan B:
    ///
    ///  · Necesita el `privatetoken` del login. Si iniciaste sesión con una
    ///    versión anterior de la app, no lo tenemos guardado.
    ///  · Moodle solo entrega una llave cada 6 minutos (configurable en el
    ///    sitio). La segunda seguida devuelve error, no una llave.
    ///  · La IP tiene que ser la misma con la que se pidió el token.
    func autologinURL(userId: Int, target: URL) async throws -> URL {
        guard let privateToken = currentPrivateToken, !privateToken.isEmpty else {
            throw APIError(message: "Esta sesión no tiene token privado. Cerrá sesión y volvé a entrar para habilitar el autologin.",
                           errorcode: "no_privatetoken")
        }
        let resp: MoodleAutologinResponse = try await rest(
            "tool_mobile_get_autologin_key",
            params: ["privatetoken": privateToken],
            as: MoodleAutologinResponse.self)

        guard let base = resp.autologinurl, let key = resp.key,
              var comps = URLComponents(string: base) else {
            throw APIError(message: "Moodle no devolvió una URL de autologin.", errorcode: nil)
        }
        comps.queryItems = [
            .init(name: "userid", value: String(userId)),
            .init(name: "key", value: key),
            .init(name: "urltogo", value: target.absoluteString)
        ]
        guard let url = comps.url else {
            throw APIError(message: "URL de autologin inválida.", errorcode: nil)
        }
        return url
    }

    // MARK: Consultas (mod_choice)

    func choices(courseIds: [Int]) async throws -> MoodleChoicesResponse {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        return try await rest("mod_choice_get_choices_by_courses",
                              params: params, as: MoodleChoicesResponse.self)
    }

    func choiceOptions(choiceId: Int) async throws -> [MoodleChoiceOption] {
        let resp: MoodleChoiceOptionsResponse = try await rest(
            "mod_choice_get_choice_options",
            params: ["choiceid": String(choiceId)],
            as: MoodleChoiceOptionsResponse.self)
        return resp.options
    }

    /// Vota. Se manda como arreglo porque Moodle permite consultas de opción
    /// múltiple; acá se usa siempre con una sola.
    func submitChoice(choiceId: Int, optionIds: [Int]) async throws {
        struct Ack: Decodable { let warnings: [MoodleWarning]? }
        var params: [String: String] = ["choiceid": String(choiceId)]
        for (i, id) in optionIds.enumerated() {
            params["responses[\(i)]"] = String(id)
        }
        let ack: Ack = try await restForm("mod_choice_submit_choice_response",
                                          params: params, as: Ack.self)
        if let w = ack.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
    }

    func deleteChoiceResponse(choiceId: Int) async throws {
        struct Ack: Decodable { let status: Bool? }
        _ = try await restForm("mod_choice_delete_choice_responses",
                               params: ["choiceid": String(choiceId)], as: Ack.self)
    }

    // MARK: Encuestas (mod_feedback)

    func feedbacks(courseIds: [Int]) async throws -> MoodleFeedbacksResponse {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        return try await rest("mod_feedback_get_feedbacks_by_courses",
                              params: params, as: MoodleFeedbacksResponse.self)
    }

    /// Los ítems de una página del formulario.
    func feedbackPage(feedbackId: Int, page: Int = 0) async throws -> MoodleFeedbackPage {
        try await rest("mod_feedback_get_page_items",
                       params: ["feedbackid": String(feedbackId), "page": String(page)],
                       as: MoodleFeedbackPage.self)
    }

    /// Envía las respuestas de una página.
    ///
    /// El formato de `responses` es de Moodle y es peculiar: la clave es
    /// `<tipo>_<idItem>` (por ejemplo `multichoice_412`), y el valor es texto
    /// libre salvo en las de opción, donde es el índice 1-based de la elegida.
    func submitFeedbackPage(feedbackId: Int, page: Int,
                            responses: [(name: String, value: String)]) async throws -> MoodleFeedbackProcessResult {
        var params: [String: String] = [
            "feedbackid": String(feedbackId),
            "page": String(page),
            "goprevious": "0"
        ]
        for (i, r) in responses.enumerated() {
            params["responses[\(i)][name]"]  = r.name
            params["responses[\(i)][value]"] = r.value
        }
        return try await restForm("mod_feedback_process_page",
                                  params: params, as: MoodleFeedbackProcessResult.self)
    }
}

// MARK: - Elección de grupo (mod_choicegroup)

extension MoodleClient {

    func choiceGroups(courseIds: [Int]) async throws -> MoodleChoiceGroupsResponse {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        return try await rest("mod_choicegroup_get_choicegroups_by_courses",
                              params: params, as: MoodleChoiceGroupsResponse.self)
    }

    func choiceGroupOptions(id: Int) async throws -> [MoodleChoiceGroupOption] {
        let resp: MoodleChoiceGroupOptionsResponse = try await rest(
            "mod_choicegroup_get_choicegroup_options",
            params: ["choicegroupid": String(id)],
            as: MoodleChoiceGroupOptionsResponse.self)
        return resp.options
    }

    /// Se anota en un grupo. Reemplaza la elección anterior si el docente
    /// permitió cambiarla.
    func submitChoiceGroup(id: Int, optionId: Int) async throws {
        struct Ack: Decodable { let warnings: [MoodleWarning]? }
        let ack: Ack = try await restForm(
            "mod_choicegroup_submit_choicegroup_response",
            params: ["choicegroupid": String(id), "responses[0]": String(optionId)],
            as: Ack.self)
        if let w = ack.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
    }

    func deleteChoiceGroupResponse(id: Int) async throws {
        struct Ack: Decodable { let status: Bool? }
        _ = try await restForm("mod_choicegroup_delete_choicegroup_responses",
                               params: ["choicegroupid": String(id)], as: Ack.self)
    }
}
