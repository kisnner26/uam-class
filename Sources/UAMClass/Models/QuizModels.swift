import Foundation

// MARK: - Modelos de cuestionarios (mod_quiz)
//
// Moodle devuelve las preguntas como HTML ya renderizado, no como datos
// estructurados. Estos tipos cubren la parte que sí viene estructurada
// (metadatos del quiz, intentos, estados); el parseo del HTML de cada pregunta
// vive en Services/QuizHTML.swift.

// MARK: Quiz

struct MoodleQuizzesResponse: Decodable {
    let quizzes: [MoodleQuiz]
    let warnings: [MoodleWarning]?
}

struct MoodleQuiz: Decodable, Identifiable, Hashable {
    let id: Int
    let coursemodule: Int?
    let course: Int?
    let name: String
    let intro: String?

    /// Ventana de disponibilidad (epoch, 0 = sin límite).
    let timeopen: Int?
    let timeclose: Int?
    /// Límite de tiempo por intento, en segundos (0 = sin límite).
    let timelimit: Int?

    /// Intentos permitidos (0 = ilimitados).
    let attempts: Int?
    /// 1 = las preguntas se mezclan entre intentos.
    let shufflequestions: Int?
    /// Preguntas por página (0 = todas en una).
    let questionsperpage: Int?
    /// Nota máxima del cuestionario.
    let grade: Double?
    let sumgrades: Double?
    /// Cómo se combina la nota entre intentos (1 = mayor, 2 = promedio, …).
    let grademethod: Int?

    /// Contraseña requerida (solo indica si existe; el valor no viene).
    let password: String?
    let hasfeedback: Int?

    var cleanIntro: String { HTMLClean.plain(intro ?? "") }

    var openDate: Date? { epoch(timeopen) }
    var closeDate: Date? { epoch(timeclose) }

    /// Límite de tiempo como intervalo, o nil si no hay.
    var timeLimitInterval: TimeInterval? {
        guard let t = timelimit, t > 0 else { return nil }
        return TimeInterval(t)
    }

    var requiresPassword: Bool { !(password ?? "").isEmpty }

    /// El cuestionario está abierto ahora mismo.
    var isOpenNow: Bool {
        let now = Date()
        if let o = openDate, now < o { return false }
        if let c = closeDate, now > c { return false }
        return true
    }

    private func epoch(_ v: Int?) -> Date? {
        guard let v, v > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(v))
    }
}

// MARK: Intentos

struct MoodleQuizAttemptsResponse: Decodable {
    let attempts: [MoodleQuizAttempt]
    let warnings: [MoodleWarning]?
}

struct MoodleQuizAttempt: Decodable, Identifiable, Hashable {
    let id: Int
    let quiz: Int?
    let userid: Int?
    /// Número de intento, empezando en 1.
    let attempt: Int?
    let uniqueid: Int?
    let layout: String?
    /// Página actual dentro del intento.
    let currentpage: Int?
    let preview: Int?
    /// "inprogress" | "overdue" | "finished" | "abandoned"
    let state: String
    let timestart: Int?
    let timefinish: Int?
    let timemodified: Int?
    let timecheckstate: Int?
    let sumgrades: Double?
    /// Presente solo cuando Moodle permite ver la nota.
    let gradednotificationsenttime: Int?

    var isInProgress: Bool { state == "inprogress" || state == "overdue" }
    var isFinished: Bool { state == "finished" }

    var startDate: Date? {
        guard let t = timestart, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var finishDate: Date? {
        guard let t = timefinish, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    var stateLabel: String {
        switch state {
        case "inprogress": return "En curso"
        case "overdue":    return "Vencido"
        case "finished":   return "Terminado"
        case "abandoned":  return "Abandonado"
        default:           return state
        }
    }
}

// MARK: Acceso

struct MoodleQuizAccessInfo: Decodable {
    let canattempt: Bool?
    let canmanage: Bool?
    let canpreview: Bool?
    let canreviewmyattempts: Bool?
    let accessrules: [String]?
    let activerulenames: [String]?
    let preventaccessreasons: [String]?
}

struct MoodleAttemptAccessInfo: Decodable {
    /// nil/true = se puede iniciar un intento nuevo.
    let isfinished: Bool?
    let ispreflightcheckrequired: Bool?
    let preventnewattemptreasons: [String]?
    let warnings: [MoodleWarning]?
}

// MARK: Datos del intento

struct MoodleAttemptDataResponse: Decodable {
    let attempt: MoodleQuizAttempt
    let messages: [String]?
    /// Siguiente página, o -1 si es la última.
    let nextpage: Int?
    let questions: [MoodleQuizQuestionPayload]
    let warnings: [MoodleWarning]?
}

/// Una pregunta tal como la manda Moodle: metadatos + HTML renderizado.
struct MoodleQuizQuestionPayload: Decodable, Identifiable, Hashable {
    let slot: Int
    /// Tipo de pregunta ("multichoice", "truefalse", "essay", …).
    /// Moodle lo omite en algunos casos de revisión.
    let type: String?
    let page: Int?
    let questionnumber: String?
    let number: Int?
    let html: String
    /// Debe reenviarse en cada guardado o Moodle rechaza la respuesta.
    let sequencecheck: Int?
    let lastactiontime: Int?
    let hasautosavedstep: Bool?
    let flagged: Bool?
    /// "todo" | "complete" | "invalid" | "gaveup" | …
    let state: String?
    let status: String?
    let blockedbyprevious: Bool?
    let maxmark: Double?
    let mark: String?

    var id: Int { slot }

    var isAnswered: Bool {
        guard let s = state else { return false }
        return s != "todo" && s != "invalid"
    }
}

struct MoodleAttemptSummaryResponse: Decodable {
    let questions: [MoodleQuizQuestionPayload]
    let warnings: [MoodleWarning]?
}

// MARK: Guardado / envío

struct MoodleQuizSaveResponse: Decodable {
    let status: Bool?
    let warnings: [MoodleWarning]?
}

struct MoodleQuizProcessResponse: Decodable {
    /// Estado del intento tras procesarlo ("finished", "inprogress", …).
    let state: String?
    let warnings: [MoodleWarning]?
}

// MARK: Revisión

struct MoodleAttemptReviewResponse: Decodable {
    let grade: String?
    let attempt: MoodleQuizAttempt
    let additionaldata: [MoodleReviewExtra]?
    let questions: [MoodleQuizQuestionPayload]
    let warnings: [MoodleWarning]?
}

struct MoodleReviewExtra: Decodable, Hashable {
    let id: String?
    let title: String?
    let content: String?
}

// MARK: Campos de formulario

/// Par nombre/valor tal como lo espera Moodle en `data[n][name|value]`.
/// Los nombres salen literales del HTML de la pregunta (`q123:1_answer`);
/// nunca se construyen a mano.
struct QuizFormField: Hashable, Codable {
    let name: String
    let value: String
}

// MARK: Warnings

struct MoodleWarning: Decodable, Hashable {
    let item: String?
    let itemid: Int?
    let warningcode: String?
    let message: String?
}
