import Foundation

/// Usuario del directorio de UAM Virtual.
///
/// `core_user_get_users_by_field` devuelve bastante más que esto, pero casi todo
/// depende de la política de privacidad del sitio: si el admin la restringe,
/// los campos llegan vacíos o directamente ausentes. Por eso todo es opcional
/// menos el id y el nombre.
struct MoodleDirectoryUser: Decodable, Identifiable, Hashable {
    let id: Int
    /// `core_user_get_users` no siempre manda `fullname`; en ese caso se arma
    /// con nombre y apellido para no perder el resultado entero.
    private let fullnameRaw: String?
    let firstname: String?
    let lastname: String?
    let username: String?
    let email: String?
    let department: String?
    let profileimageurl: String?
    let profileimageurlsmall: String?
    let firstaccess: Int?
    let lastaccess: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case fullnameRaw = "fullname"
        case firstname, lastname, username, email, department
        case profileimageurl, profileimageurlsmall, firstaccess, lastaccess
    }

    var fullname: String {
        if let f = fullnameRaw?.trimmingCharacters(in: .whitespaces), !f.isEmpty { return f }
        let parts = [firstname, lastname].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Sin nombre" : parts.joined(separator: " ")
    }

    var displayName: String { Fmt.properName(fullname) }
    var initials: String { Fmt.initials(fullname) }

    /// El CIF es el `username` en Moodle de UAM.
    var cif: String? {
        guard let u = username, !u.isEmpty else { return nil }
        return u.uppercased()
    }

    var lastAccessDate: Date? {
        guard let t = lastaccess, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    /// Resultado de `core_message_search_users`, que solo trae nombre y avatar.
    /// Sirve como respaldo cuando el sitio no deja enriquecerlo por campo.
    init(fromSearch u: MoodleSearchUser) {
        self.id = u.id
        self.fullnameRaw = u.fullname
        self.firstname = nil
        self.lastname = nil
        self.username = nil
        self.email = nil
        self.department = nil
        self.profileimageurl = u.profileimageurl
        self.profileimageurlsmall = u.profileimageurlsmall
        self.firstaccess = nil
        self.lastaccess = nil
    }
}

/// `core_user_get_users` envuelve los resultados; `..._by_field` no.
struct MoodleUsersQueryResponse: Decodable {
    let users: [MoodleDirectoryUser]
}

// MARK: - Bloques

/// `core_block_get_course_blocks` / `core_block_get_dashboard_blocks`.
/// `contents.content` es HTML ya renderizado por el sitio.
struct MoodleBlocksResponse: Decodable {
    let blocks: [MoodleBlock]
}

struct MoodleBlock: Decodable, Identifiable, Hashable {
    let instanceid: Int
    let name: String
    let contents: Contents?

    var id: Int { instanceid }

    struct Contents: Decodable, Hashable {
        let title: String?
        let content: String?
        let footer: String?
    }
}
