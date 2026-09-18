import Foundation

// MARK: - API de cuestionarios
//
// Todo lo que escribe (guardar respuestas, procesar el intento) va por
// `restForm`, es decir por cuerpo POST. Ver la nota en MoodleClient.restForm.

extension MoodleClient {

    // MARK: Listado

    func quizzes(courseIds: [Int]) async throws -> MoodleQuizzesResponse {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() {
            params["courseids[\(i)]"] = String(id)
        }
        return try await rest("mod_quiz_get_quizzes_by_courses",
                              params: params,
                              as: MoodleQuizzesResponse.self)
    }

    // MARK: Acceso

    func quizAccessInfo(quizId: Int) async throws -> MoodleQuizAccessInfo {
        try await rest("mod_quiz_get_quiz_access_information",
                       params: ["quizid": String(quizId)],
                       as: MoodleQuizAccessInfo.self)
    }

    func attemptAccessInfo(quizId: Int, attemptId: Int? = nil) async throws -> MoodleAttemptAccessInfo {
        var params = ["quizid": String(quizId)]
        if let attemptId { params["attemptid"] = String(attemptId) }
        return try await rest("mod_quiz_get_attempt_access_information",
                              params: params,
                              as: MoodleAttemptAccessInfo.self)
    }

    // MARK: Intentos

    func quizAttempts(quizId: Int,
                      userId: Int? = nil,
                      status: String = "all") async throws -> MoodleQuizAttemptsResponse {
        var params = [
            "quizid": String(quizId),
            "status": status,
            "includepreviews": "0"
        ]
        if let userId { params["userid"] = String(userId) }
        return try await rest("mod_quiz_get_user_attempts",
                              params: params,
                              as: MoodleQuizAttemptsResponse.self)
    }

    /// Inicia un intento nuevo. `password` solo si el cuestionario lo pide.
    func startAttempt(quizId: Int, password: String? = nil) async throws -> MoodleQuizAttempt {
        struct Response: Decodable {
            let attempt: MoodleQuizAttempt
            let warnings: [MoodleWarning]?
        }
        var params: [String: String] = [
            "quizid": String(quizId),
            "forcenew": "0"
        ]
        if let password, !password.isEmpty {
            params["preflightdata[0][name]"]  = "quizpassword"
            params["preflightdata[0][value]"] = password
        }
        let r: Response = try await restForm("mod_quiz_start_attempt",
                                             params: params,
                                             as: Response.self)
        return r.attempt
    }

    /// Trae las preguntas de una página del intento, como HTML renderizado.
    func attemptData(attemptId: Int,
                     page: Int,
                     password: String? = nil) async throws -> MoodleAttemptDataResponse {
        var params: [String: String] = [
            "attemptid": String(attemptId),
            "page": String(page)
        ]
        if let password, !password.isEmpty {
            params["preflightdata[0][name]"]  = "quizpassword"
            params["preflightdata[0][value]"] = password
        }
        return try await restForm("mod_quiz_get_attempt_data",
                                  params: params,
                                  as: MoodleAttemptDataResponse.self)
    }

    /// Resumen con el estado de todas las preguntas del intento.
    func attemptSummary(attemptId: Int,
                        password: String? = nil) async throws -> MoodleAttemptSummaryResponse {
        var params: [String: String] = ["attemptid": String(attemptId)]
        if let password, !password.isEmpty {
            params["preflightdata[0][name]"]  = "quizpassword"
            params["preflightdata[0][value]"] = password
        }
        return try await restForm("mod_quiz_get_attempt_summary",
                                  params: params,
                                  as: MoodleAttemptSummaryResponse.self)
    }

    // MARK: Guardar / enviar

    /// Guarda respuestas sin cerrar el intento (autoguardado).
    @discardableResult
    func saveAttempt(attemptId: Int,
                     data: [QuizFormField],
                     password: String? = nil) async throws -> MoodleQuizSaveResponse {
        var params: [String: String] = ["attemptid": String(attemptId)]
        for (i, field) in data.enumerated() {
            params["data[\(i)][name]"]  = field.name
            params["data[\(i)][value]"] = field.value
        }
        if let password, !password.isEmpty {
            params["preflightdata[0][name]"]  = "quizpassword"
            params["preflightdata[0][value]"] = password
        }
        return try await restForm("mod_quiz_save_attempt",
                                  params: params,
                                  as: MoodleQuizSaveResponse.self)
    }

    /// Procesa el intento. Con `finish: true` lo cierra y lo manda a calificar
    /// — es irreversible desde el lado del estudiante.
    @discardableResult
    func processAttempt(attemptId: Int,
                        data: [QuizFormField],
                        finish: Bool,
                        timeUp: Bool = false,
                        password: String? = nil) async throws -> MoodleQuizProcessResponse {
        var params: [String: String] = [
            "attemptid": String(attemptId),
            "finishattempt": finish ? "1" : "0",
            "timeup": timeUp ? "1" : "0"
        ]
        for (i, field) in data.enumerated() {
            params["data[\(i)][name]"]  = field.name
            params["data[\(i)][value]"] = field.value
        }
        if let password, !password.isEmpty {
            params["preflightdata[0][name]"]  = "quizpassword"
            params["preflightdata[0][value]"] = password
        }
        return try await restForm("mod_quiz_process_attempt",
                                  params: params,
                                  as: MoodleQuizProcessResponse.self)
    }

    // MARK: Revisión

    func attemptReview(attemptId: Int, page: Int = -1) async throws -> MoodleAttemptReviewResponse {
        try await restForm("mod_quiz_get_attempt_review",
                           params: [
                               "attemptid": String(attemptId),
                               "page": String(page)
                           ],
                           as: MoodleAttemptReviewResponse.self)
    }

    // MARK: Registro de vista
    //
    // Moodle marca el módulo como visto y dispara los eventos de log. No es
    // opcional: sin esto el docente ve el intento como "nunca abierto".

    func markQuizViewed(quizId: Int) async {
        struct Ack: Decodable { let status: Bool? }
        _ = try? await rest("mod_quiz_view_quiz",
                            params: ["quizid": String(quizId)],
                            as: Ack.self)
    }

    func markAttemptViewed(attemptId: Int, page: Int) async {
        struct Ack: Decodable { let status: Bool? }
        _ = try? await rest("mod_quiz_view_attempt",
                            params: [
                                "attemptid": String(attemptId),
                                "page": String(page)
                            ],
                            as: Ack.self)
    }
}
