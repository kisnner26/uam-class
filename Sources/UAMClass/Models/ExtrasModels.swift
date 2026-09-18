import Foundation

// MARK: - Insignias

struct MoodleBadgesResponse: Decodable {
    let badges: [MoodleBadge]
}

/// Una insignia ganada. Moodle devuelve bastante más; se modela lo que sirve
/// para mostrarla y todo es opcional menos el nombre, porque los campos varían
/// según si la insignia es del sitio o de un curso.
struct MoodleBadge: Decodable, Hashable, Identifiable {
    /// El id numérico de Moodle. Puede venir nulo, así que NO sirve como
    /// identidad: se usa `uniquehash`, que es el que Moodle garantiza único.
    let numericID: Int?
    let name: String
    let description: String?
    let badgeurl: String?
    let issuername: String?
    let courseid: Int?
    let dateissued: Int?
    let dateexpire: Int?
    /// 1 = del sitio, 2 = de un curso.
    let type: Int?
    let uniquehash: String?

    enum CodingKeys: String, CodingKey {
        case numericID = "id"
        case name, description, badgeurl, issuername, courseid
        case dateissued, dateexpire, type, uniquehash
    }

    var identity: String { uniquehash ?? "\(numericID ?? 0)-\(name)" }
    var id: String { identity }

    var issued: Date? {
        guard let t = dateissued, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    var expired: Bool {
        guard let t = dateexpire, t > 0 else { return false }
        return Date(timeIntervalSince1970: TimeInterval(t)) < Date()
    }

    var cleanDescription: String { HTMLClean.plain(description) }
    var isSiteWide: Bool { (type ?? 2) == 1 }
}

// MARK: - Autologin

struct MoodleAutologinResponse: Decodable {
    let key: String?
    let autologinurl: String?
}

// Los avisos genéricos (`MoodleWarning`) ya viven en QuizModels.

// MARK: - Consultas (mod_choice)

struct MoodleChoicesResponse: Decodable {
    let choices: [MoodleChoice]
}

struct MoodleChoice: Decodable, Identifiable, Hashable {
    let id: Int
    let coursemodule: Int?
    let course: Int?
    let name: String
    let intro: String?
    let allowmultiple: Bool?
    let allowupdate: Bool?
    let showresults: Int?
    let timeopen: Int?
    let timeclose: Int?

    var cleanIntro: String { HTMLClean.plain(intro) }

    var isOpen: Bool {
        let now = Int(Date().timeIntervalSince1970)
        if let o = timeopen, o > 0, now < o { return false }
        if let c = timeclose, c > 0, now > c { return false }
        return true
    }
}

struct MoodleChoiceOptionsResponse: Decodable {
    let options: [MoodleChoiceOption]
}

struct MoodleChoiceOption: Decodable, Identifiable, Hashable {
    let id: Int
    let text: String
    let maxanswers: Int?
    let countanswers: Int?
    /// Si ya votaste esta opción.
    let checked: Bool?
    /// Si está llena o cerrada.
    let disabled: Bool?

    var cleanText: String { HTMLClean.plain(text) }
    var isFull: Bool {
        guard let max = maxanswers, max > 0, let count = countanswers else { return false }
        return count >= max
    }
}

// MARK: - Encuestas (mod_feedback)

struct MoodleFeedbacksResponse: Decodable {
    let feedbacks: [MoodleFeedback]
}

struct MoodleFeedback: Decodable, Identifiable, Hashable {
    let id: Int
    let coursemodule: Int?
    let course: Int?
    let name: String
    let intro: String?
    let anonymous: Int?
    let multiple_submit: Bool?
    let timeopen: Int?
    let timeclose: Int?

    var cleanIntro: String { HTMLClean.plain(intro) }
    var isAnonymous: Bool { (anonymous ?? 1) == 1 }
}

struct MoodleFeedbackPage: Decodable {
    let items: [MoodleFeedbackItem]
    let hasprevpage: Bool?
    let hasnextpage: Bool?
}

/// Un campo del formulario.
///
/// `typ` es lo que decide todo: `textfield`, `textarea`, `numeric`,
/// `multichoice`, `multichoicerated`, `info`, `label`, `captcha`, `pagebreak`.
struct MoodleFeedbackItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let label: String?
    let typ: String?
    let presentation: String?
    let required: Bool?
    let itemnumber: Int?
    /// El nombre que espera `mod_feedback_process_page` para esta respuesta.
    let otherdata: String?

    var cleanName: String { HTMLClean.plain(name) }

    /// Clave de la respuesta: `<tipo>_<id>`. Es el formato que exige Moodle.
    var responseKey: String { "\(typ ?? "textfield")_\(id)" }

    /// Las opciones de un `multichoice` vienen empaquetadas en `presentation`,
    /// separadas por `|`, con un prefijo que indica el modo de despliegue
    /// (`r>` radio, `c>` casillas, `d>` desplegable).
    var choices: [String] {
        guard let p = presentation, !p.isEmpty else { return [] }
        let body = p.contains(">>>>>") ? String(p.split(separator: ">").last ?? "") : p
        return body.split(separator: "|")
            .map { HTMLClean.plain(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// ¿Se puede responder desde la app, o hay que mandar a Moodle?
    var isSupported: Bool {
        switch typ {
        case "textfield", "textarea", "numeric": return true
        case "multichoice": return !choices.isEmpty && !allowsMultiple
        default: return false
        }
    }

    /// Casillas (varias respuestas) — no soportado todavía: la codificación de
    /// respuestas múltiples de Moodle es distinta y sin poder probarla contra el
    /// servidor prefiero no adivinarla.
    var allowsMultiple: Bool { (presentation ?? "").hasPrefix("c") }

    var isDisplayOnly: Bool { typ == "label" || typ == "info" || typ == "pagebreak" }
}

struct MoodleFeedbackProcessResult: Decodable {
    let jumpto: Int?
    let completed: Bool?
    let completionpagecontents: String?
    let warnings: [MoodleWarning]?
}

// MARK: - Elección de grupo (mod_choicegroup)
//
// Plugin de terceros: sirve para que el estudiante elija en qué grupo de trabajo
// se anota. La forma de la API es casi igual a la de `mod_choice`, pero las
// opciones son GRUPOS del curso, no respuestas sueltas — y eso cambia lo que
// importa mostrar: no el conteo, sino QUIÉN está en cada uno.

struct MoodleChoiceGroupsResponse: Decodable {
    let choicegroups: [MoodleChoiceGroup]
}

struct MoodleChoiceGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let coursemodule: Int?
    let course: Int?
    let name: String
    let intro: String?
    let timeopen: Int?
    let timeclose: Int?
    let allowupdate: Bool?
    let limitanswers: Bool?
    let showresults: Int?

    var cleanIntro: String { HTMLClean.plain(intro) }

    var isOpen: Bool {
        let now = Int(Date().timeIntervalSince1970)
        if let o = timeopen, o > 0, now < o { return false }
        if let c = timeclose, c > 0, now > c { return false }
        return true
    }

    var closesAt: Date? {
        guard let t = timeclose, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
}

struct MoodleChoiceGroupOptionsResponse: Decodable {
    let options: [MoodleChoiceGroupOption]
}

struct MoodleChoiceGroupOption: Decodable, Identifiable, Hashable {
    let id: Int
    let text: String
    let maxanswers: Int?
    let countanswers: Int?
    let checked: Bool?
    let disabled: Bool?

    var groupName: String { HTMLClean.plain(text) }

    var isFull: Bool {
        guard let max = maxanswers, max > 0, let count = countanswers else { return false }
        return count >= max
    }

    var occupancy: String {
        let count = countanswers ?? 0
        if let max = maxanswers, max > 0 { return "\(count) de \(max)" }
        return "\(count) inscrito\(count == 1 ? "" : "s")"
    }
}
