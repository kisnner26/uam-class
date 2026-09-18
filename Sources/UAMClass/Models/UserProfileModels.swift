import Foundation

/// Perfil de usuario devuelto por `core_user_get_course_user_profiles`.
///
/// Casi todo es opcional a propósito: cuánto llega depende de la política de
/// privacidad del sitio y de si compartís curso con esa persona. Un campo nil
/// no es un error, es "no me lo dejaron ver".
struct MoodleUserProfile: Decodable, Identifiable, Hashable {
    let id: Int
    let fullname: String
    let firstname: String?
    let lastname: String?
    let email: String?
    let username: String?
    let idnumber: String?
    let department: String?
    let institution: String?
    let address: String?
    let phone1: String?
    let city: String?
    let country: String?
    let description: String?
    let profileimageurl: String?
    let firstaccess: Int?
    let lastaccess: Int?
    let lastcourseaccess: Int?
    let roles: [MoodleRole]?
    let groups: [MoodleGroup]?
    /// Solo llega si el sitio lo permite.
    let enrolledcourses: [MoodleEnrolledCourseRef]?

    var displayName: String { Fmt.properName(fullname) }
    var initials: String { Fmt.initials(fullname) }

    var cif: String? {
        for c in [username, idnumber] {
            if let v = c?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                return v.uppercased()
            }
        }
        return nil
    }

    /// La carrera suele venir en `department`; algunos sitios usan `institution`.
    var program: String? {
        for c in [department, institution] {
            if let v = c?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v }
        }
        return nil
    }

    var cleanDescription: String { HTMLClean.plain(description) }

    var lastAccessDate: Date? {
        guard let t = lastaccess, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var firstAccessDate: Date? {
        guard let t = firstaccess, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
}

struct MoodleEnrolledCourseRef: Decodable, Hashable, Identifiable {
    let id: Int
    let fullname: String?
    let shortname: String?
}
