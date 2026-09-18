import Foundation

// MARK: - Login

struct MoodleTokenResponse: Decodable {
    let token: String?
    let privatetoken: String?
    // Error fields
    let error: String?
    let errorcode: String?
}

// MARK: - Site info

struct MoodleSiteInfo: Decodable, Identifiable {
    let userid: Int
    let fullname: String
    let username: String
    let sitename: String
    let firstname: String?
    let lastname: String?
    let userpictureurl: String?
    let lang: String?
    let release: String?
    /// Funciones de web service habilitadas para este token. Sirve para saber
    /// qué plugins tiene el sitio (p. ej. `mod_attendance_*`) ANTES de llamar y
    /// comerse un error.
    let functions: [MoodleFunctionInfo]?

    var id: Int { userid }

    private var functionNames: Set<String> {
        Set((functions ?? []).map(\.name))
    }

    func hasFunction(_ name: String) -> Bool { functionNames.contains(name) }

    /// El plugin de asistencia (mod_attendance) es de terceros: hay sitios de
    /// Moodle que no lo tienen instalado.
    var supportsAttendance: Bool {
        hasFunction("mod_attendance_get_courses_with_today_sessions")
    }

    /// `mod_choicegroup` (elegir grupo de trabajo) también es de terceros.
    /// Preguntar antes de llamar evita el error críptico de Moodle cuando la
    /// función no existe.
    var supportsChoiceGroup: Bool {
        hasFunction("mod_choicegroup_get_choicegroups_by_courses")
    }
}

struct MoodleFunctionInfo: Decodable, Hashable {
    let name: String
    let version: String?
}

// MARK: - Cursos

struct MoodleCourse: Codable, Identifiable, Hashable {
    let id: Int
    let shortname: String
    let fullname: String
    let displayname: String?
    let idnumber: String?
    let visible: Int?
    let category: Int?
    let progress: Double?
    let hidden: Bool?
    let startdate: Int?
    let enddate: Int?
    /// URL del thumbnail principal del curso (WebService lo devuelve como `courseimage`).
    let courseimage: String?
    /// Archivos "overview" del curso (imágenes de banner, subidas por el docente).
    let overviewfiles: [MoodleContentFile]?

    var displayTitle: String { displayname ?? fullname }

    /// Mejor URL de imagen disponible (tokenizable via MoodleClient).
    var imageURL: String? {
        if let ci = courseimage, !ci.isEmpty { return ci }
        return overviewfiles?.first?.fileurl
    }
}

// MARK: - Asignaciones (mod_assign)

struct MoodleAssignmentsResponse: Codable {
    let courses: [MoodleAssignmentCourse]
}

struct MoodleAssignmentCourse: Codable, Identifiable {
    let id: Int
    let fullname: String
    let shortname: String
    let assignments: [MoodleAssignment]
}

struct MoodleAssignment: Codable, Identifiable, Hashable {
    let id: Int
    let cmid: Int?
    let course: Int
    let name: String
    let intro: String?
    let duedate: Int?         // epoch
    let allowsubmissionsfromdate: Int?
    let cutoffdate: Int?
    let grade: Double?
    /// Archivos que el docente adjuntó al enunciado (la consigna en PDF, la
    /// rúbrica, la plantilla). Sin esto, resolver la tarea sería adivinar.
    let introattachments: [MoodleContentFile]?

    var dueDateOrNil: Date? {
        guard let d = duedate, d > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(d))
    }
}

// MARK: - Notas (gradereport_user_get_grade_items)

struct MoodleGradesResponse: Codable {
    let usergrades: [MoodleUserGrade]
}

struct MoodleUserGrade: Codable, Identifiable {
    let courseid: Int
    let userid: Int?
    let userfullname: String?
    let courseidnumber: String?
    let gradeitems: [MoodleGradeItem]

    var id: Int { courseid }
}

struct MoodleGradeItem: Codable, Identifiable, Hashable {
    let id: Int
    let itemname: String?
    let itemtype: String?
    let itemmodule: String?
    let categoryid: Int?
    let graderaw: Double?
    let gradeformatted: String?
    let grademax: Double?
    let grademin: Double?
    let percentageformatted: String?
    let feedback: String?

    var displayName: String {
        let raw = HTMLClean.plain(itemname)
        return raw.isEmpty ? "(sin nombre)" : raw
    }

    /// gradeformatted a veces trae HTML como `<i class="fa fa-check" title="Aprobado"></i>7,00`.
    /// Extraemos: (número visible, badge si aplica).
    var displayGrade: String { HTMLClean.plain(gradeformatted) }
    var badge: HTMLClean.Badge? { HTMLClean.extractBadge(gradeformatted) }

    /// Comentario/feedback del docente sin HTML.
    var cleanFeedback: String { HTMLClean.plain(feedback) }
    var hasFeedback: Bool { !cleanFeedback.isEmpty }

    /// Ítems auto-generados por Moodle que no tienen nombre real (categorías, totales).
    var isMeta: Bool {
        let n = itemname ?? ""
        return n.isEmpty || itemtype == "category" || itemtype == "course"
    }
}

// MARK: - Course contents (core_course_get_contents)

struct MoodleCourseSection: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let visible: Int?
    let summary: String?
    let section: Int?
    let modules: [MoodleModule]

    var cleanSummary: String { HTMLClean.plain(summary) }
    var displayName: String {
        let n = HTMLClean.plain(name)
        return n.isEmpty ? "Sección \(section ?? 0)" : n
    }
}

struct MoodleModule: Codable, Identifiable, Hashable {
    let id: Int
    let url: String?
    let name: String
    let instance: Int?
    let visible: Int?
    let modicon: String?
    let modname: String
    let modplural: String?
    let description: String?
    let contents: [MoodleContentFile]?
    let dates: [MoodleModuleDate]?

    var displayName: String {
        let n = HTMLClean.plain(name)
        return n.isEmpty ? modname : n
    }
    var cleanDescription: String { HTMLClean.plain(description) }
}

struct MoodleModuleDate: Codable, Hashable {
    let label: String?
    let timestamp: Int?

    var date: Date? {
        guard let t = timestamp, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
}

struct MoodleContentFile: Codable, Hashable, Identifiable {
    let type: String?
    let filename: String?
    let filepath: String?
    let filesize: Int?
    let fileurl: String?
    let timemodified: Int?
    let mimetype: String?

    var id: String { (fileurl ?? "") + "|" + (filename ?? "") }
    var displayName: String { filename ?? "archivo" }
    var displaySize: String {
        guard let bytes = filesize, bytes > 0 else { return "" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
    var isImage: Bool { (mimetype ?? "").hasPrefix("image/") }
    var isPDF: Bool { mimetype == "application/pdf" }
    var isVideo: Bool { (mimetype ?? "").hasPrefix("video/") }
}

// MARK: - Enrolled users (profesores + compañeros)

struct MoodleEnrolledUser: Decodable, Identifiable, Hashable {
    let id: Int
    let fullname: String
    let firstname: String?
    let lastname: String?
    let email: String?
    let profileimageurl: String?
    let profileimageurlsmall: String?
    let roles: [MoodleRole]?
    let city: String?
    let country: String?
    /// El CIF. Moodle solo lo manda si el sitio expone la identidad del usuario
    /// (`moodle/site:viewuseridentity`); si no, llega nil.
    let username: String?
    let idnumber: String?
    let department: String?
    let institution: String?
    let lastaccess: Int?
    let groups: [MoodleGroup]?

    var displayName: String { fullname }

    /// CIF en mayúsculas, de donde esté disponible.
    var cif: String? {
        for candidate in [username, idnumber] {
            if let c = candidate?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
                return c.uppercased()
            }
        }
        return nil
    }

    var lastAccessDate: Date? {
        guard let t = lastaccess, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var isTeacher: Bool {
        (roles ?? []).contains { r in
            let s = r.shortname.lowercased()
            return s.contains("teacher") || s.contains("editingteacher") || s.contains("docente")
        }
    }
    var primaryRole: String {
        if let r = (roles ?? []).first { return r.name }
        return ""
    }
}

struct MoodleGroup: Decodable, Hashable {
    let id: Int
    let name: String?
}

struct MoodleRole: Decodable, Hashable {
    let roleid: Int
    let name: String
    let shortname: String
    let sortorder: Int?
}

// MARK: - Foros

struct MoodleForum: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int
    let type: String?
    let name: String
    let intro: String?
    let cmid: Int?

    var cleanIntro: String { HTMLClean.plain(intro) }
}

struct MoodleDiscussionsResponse: Decodable {
    let discussions: [MoodleForumDiscussion]
}

struct MoodleForumDiscussion: Decodable, Identifiable, Hashable {
    let id: Int
    let discussion: Int?     // A veces viene como "discussion" en vez de "id"
    let name: String
    let subject: String?
    let message: String?
    let userfullname: String?
    let userpictureurl: String?
    let created: Int?
    let timemodified: Int?
    let numreplies: Int?

    var when: Date? {
        guard let t = created, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var cleanMessage: String { HTMLClean.plain(message) }
    var discussionId: Int { discussion ?? id }
}

struct MoodleForumPostsResponse: Decodable {
    let posts: [MoodleForumPost]
}

struct MoodleForumPost: Decodable, Identifiable, Hashable {
    let id: Int
    let subject: String?
    let message: String?
    let author: MoodlePostAuthor?
    let timecreated: Int?
    let parentid: Int?

    var when: Date? {
        guard let t = timecreated, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var cleanMessage: String { HTMLClean.plain(message) }
    var cleanSubject: String { HTMLClean.plain(subject) }
}

struct MoodlePostAuthor: Decodable, Hashable {
    let id: Int?
    let fullname: String?
    let urls: MoodlePostAuthorURLs?
}

struct MoodlePostAuthorURLs: Decodable, Hashable {
    let profileimage: String?
}

// MARK: - Estado de submission de tarea

struct MoodleAssignSubmissionStatus: Decodable {
    let lastattempt: MoodleAssignLastAttempt?
}

struct MoodleAssignLastAttempt: Decodable {
    let submission: MoodleAssignSubmission?
    let feedback: MoodleAssignFeedback?
    let canedit: Bool?
    let cansubmit: Bool?
    let submissionsenabled: Bool?
    let extensionduedate: Int?
}

struct MoodleAssignSubmission: Decodable {
    let status: String?
    let timemodified: Int?
    let gradingstatus: String?
    let plugins: [MoodleAssignPlugin]?

    /// Los archivos que YA están entregados, de cualquier plugin de archivos.
    var files: [MoodleAssignFile] {
        (plugins ?? []).flatMap { $0.fileareas ?? [] }.flatMap { $0.files ?? [] }
    }

    var isDraft: Bool { status == "draft" }
    var isSubmitted: Bool { status == "submitted" }
}

struct MoodleAssignPlugin: Decodable {
    let type: String?
    let name: String?
    let fileareas: [MoodleAssignFileArea]?
}

struct MoodleAssignFileArea: Decodable {
    let area: String?
    let files: [MoodleAssignFile]?
}

struct MoodleAssignFile: Decodable, Identifiable, Hashable {
    let filename: String?
    let filesize: Int?
    let fileurl: String?
    let mimetype: String?
    let timemodified: Int?

    var id: String { (fileurl ?? "") + (filename ?? "") }
    var displayName: String { filename ?? "archivo" }

    var sizeText: String? {
        guard let b = filesize, b > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}

/// Respuesta de `webservice/upload.php`. El `itemid` a veces llega como número
/// y a veces como texto, según la versión de Moodle.
struct MoodleUploadedFile: Decodable {
    let filename: String?
    let itemid: Int

    enum CodingKeys: String, CodingKey { case filename, itemid }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filename = try? c.decode(String.self, forKey: .filename)
        if let i = try? c.decode(Int.self, forKey: .itemid) {
            itemid = i
        } else if let s = try? c.decode(String.self, forKey: .itemid), let i = Int(s) {
            itemid = i
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .itemid, in: c,
                debugDescription: "itemid ausente o ilegible")
        }
    }
}

struct MoodleAssignFeedback: Decodable {
    let grade: MoodleFeedbackGrade?
    let gradefordisplay: String?
}

struct MoodleFeedbackGrade: Decodable {
    let grade: String?
    let grader: Int?
    let dategraded: Int?
}

// MARK: - Mensajería

struct MoodleConversationsResponse: Decodable {
    let conversations: [MoodleConversation]
}

struct MoodleConversation: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let subname: String?
    let imageurl: String?
    let type: Int
    let membercount: Int?
    let ismuted: Bool?
    let isfavourite: Bool?
    let isread: Bool?
    let unreadcount: Int?
    let members: [MoodleConvMember]?
    let messages: [MoodleMessage]?

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let members = members, members.count >= 1 { return members[0].fullname }
        return "Sin nombre"
    }
    var lastMessage: MoodleMessage? { messages?.last }
    var isGroup: Bool { type == 2 }
}

struct MoodleConvMember: Decodable, Hashable, Identifiable {
    let id: Int
    let fullname: String
    let profileimageurl: String?
    let profileimageurlsmall: String?
    let isonline: Bool?
}

struct MoodleMessagesResponse: Decodable {
    let id: Int?
    let members: [MoodleConvMember]?
    let messages: [MoodleMessage]
}

struct MoodleMessage: Decodable, Identifiable, Hashable {
    let id: Int
    let useridfrom: Int
    let text: String
    let timecreated: Int?

    var when: Date? {
        guard let t = timecreated, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
    var clean: String { HTMLClean.plain(text) }
}

// core_message_search_users
struct MoodleUserSearchResponse: Decodable {
    let contacts: [MoodleSearchUser]
    let noncontacts: [MoodleSearchUser]
    // no incluimos course/messages
}

struct MoodleSearchUser: Decodable, Identifiable, Hashable {
    let id: Int
    let fullname: String
    let profileimageurl: String?
    let profileimageurlsmall: String?
    let isonline: Bool?
}
