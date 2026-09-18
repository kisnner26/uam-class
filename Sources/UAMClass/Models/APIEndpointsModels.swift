import Foundation

// MARK: - Modelos para las oportunidades de `APIAudit`
//
// Un tipo por función nueva que consume `MoodleClient+Endpoints.swift`.
// Se decodifica solo lo que la app realmente usa; Moodle manda mucho más.

// MARK: Agenda unificada (core_calendar_*)

struct MoodleTimesortEventsResponse: Decodable {
    let events: [MoodleTimesortEvent]?
}

struct MoodleTimesortEvent: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let courseid: Int?
    let timestart: Int?
    let timesort: Int?
    let timeduration: Int?
    let eventtype: String?
    let modulename: String?
    let url: String?
    let course: MoodleCalendarCourseRef?
}

struct MoodleCalendarCourseRef: Decodable, Hashable {
    let id: Int
    let fullname: String?
    let shortname: String?
}

struct MoodleMonthlyViewResponse: Decodable {
    let url: String?
    let courseid: Int?
    let weeks: [MoodleCalendarWeek]?
}

struct MoodleCalendarWeek: Decodable {
    let days: [MoodleCalendarDay]
}

struct MoodleCalendarDay: Decodable {
    let seconds: Int?
    let mday: Int?
    let events: [MoodleTimesortEvent]?
}

/// Eventos propios (crear/borrar).
struct MoodleCreatedEventsResponse: Decodable {
    let events: [MoodleTimesortEvent]?
    let warnings: [MoodleWarning]?
}

// MARK: - Notificaciones reales de Moodle

struct MoodlePopupNotificationsResponse: Decodable {
    let notifications: [MoodlePopupNotification]
    let unreadcount: Int?
}

struct MoodlePopupNotification: Decodable, Identifiable, Hashable {
    let id: Int
    let subject: String?
    let fullmessage: String?
    let fullmessagehtml: String?
    let smallmessage: String?
    let useridfrom: Int?
    let useridto: Int?
    let read: Bool?
    let timecreated: Int?
    let contexturl: String?
    let contexturlname: String?
}

struct MoodleUnreadConversationsCount: Decodable {
    // `core_message_get_unread_conversations_count` devuelve un entero pelado.
    let count: Int
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        count = try container.decode(Int.self)
    }
}

// MARK: - Progreso real por actividad (core_completion_*)

struct MoodleActivitiesCompletionResponse: Decodable {
    let statuses: [MoodleActivityCompletionStatus]
}

struct MoodleActivityCompletionStatus: Decodable, Identifiable, Hashable {
    var id: Int { cmid }
    let cmid: Int
    let modname: String?
    let instance: Int?
    let state: Int?          // 0 no, 1 sí, 2 sí (aprobado), 3 sí (no aprobado)
    let timecompleted: Int?
    let tracking: Int?       // 0 sin seguimiento, 1 manual, 2 automático
}

// MARK: - Búsqueda global (core_search_get_results)

struct MoodleSearchResultsResponse: Decodable {
    let results: [MoodleSearchResult]
    let totalcount: Int?
}

struct MoodleSearchResult: Decodable, Identifiable, Hashable {
    var id: String { "\(itemid)-\(title)" }
    let itemid: Int
    let title: String
    let content: String?
    let contextname: String?
    let courseurl: String?
    let url: String?
    let filename: String?
}

// MARK: - Notas del docente (core_notes_get_course_notes)

struct MoodleCourseNotesResponse: Decodable {
    let notes: MoodleCourseNotesByType?
}

struct MoodleCourseNotesByType: Decodable {
    let personal: [MoodleCourseNote]?
    let course: [MoodleCourseNote]?
    let site: [MoodleCourseNote]?
}

struct MoodleCourseNote: Decodable, Identifiable, Hashable {
    let id: Int
    let content: String?
    let format: Int?
    let publishstate: String?
    let coursename: String?
    let timecreated: Int?
    let lastmodified: Int?
    let usermodified: Int?
}

// MARK: - Notas de todas las materias (gradereport_overview_get_course_grades)

struct MoodleOverviewGradesResponse: Decodable {
    let grades: [MoodleOverviewGrade]
}

struct MoodleOverviewGrade: Decodable, Identifiable, Hashable {
    var id: Int { courseid }
    let courseid: Int
    let grade: String?
    let rawgrade: String?
}

// MARK: - Lecciones (mod_lesson_*)

struct MoodleLessonsByCoursesResponse: Decodable {
    let lessons: [MoodleLesson]
}

struct MoodleLesson: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let name: String?
    let intro: String?
    let timelimit: Int?
    let deadline: Int?
    let available: Int?
}

struct MoodleLessonAttemptResponse: Decodable {
    let newpageid: Int?
    let inmediatejump: Bool?
    let warnings: [MoodleWarning]?
}

struct MoodleLessonPageDataResponse: Decodable {
    let page: MoodleLessonPage?
    let pagecontent: String?
    let answers: [MoodleLessonAnswer]?
    let warnings: [MoodleWarning]?
}

struct MoodleLessonPage: Decodable, Hashable {
    let id: Int?
    let lessonid: Int?
    let title: String?
    let contents: String?
    let qtype: Int?
    let qoption: Bool?
}

struct MoodleLessonAnswer: Decodable, Identifiable, Hashable {
    var id: Int { answerid ?? 0 }
    let answerid: Int?
    let answer: String?
    let response: String?
}

// MARK: - Talleres (mod_workshop_*)

struct MoodleWorkshopsByCoursesResponse: Decodable {
    let workshops: [MoodleWorkshop]
}

struct MoodleWorkshop: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let name: String?
    let intro: String?
    let phase: Int?
    let submissionstart: Int?
    let submissionend: Int?
    let assessmentstart: Int?
    let assessmentend: Int?
}

struct MoodleWorkshopSubmissionAssessmentsResponse: Decodable {
    let assessments: [MoodleWorkshopAssessment]
}

struct MoodleWorkshopAssessment: Decodable, Identifiable, Hashable {
    let id: Int
    let submissionid: Int?
    let reviewerid: Int?
    let grade: String?
    let feedbackauthor: String?
    let timecreated: Int?
    let timemodified: Int?
}

// MARK: - Glosarios (mod_glossary_*)

struct MoodleGlossariesByCoursesResponse: Decodable {
    let glossaries: [MoodleGlossary]
}

struct MoodleGlossary: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let coursemodule: Int?
    let name: String?
    let intro: String?
}

struct MoodleGlossaryEntriesResponse: Decodable {
    let entries: [MoodleGlossaryEntry]
    let count: Int?
}

struct MoodleGlossaryEntry: Decodable, Identifiable, Hashable {
    let id: Int
    let glossaryid: Int?
    let concept: String?
    let definition: String?
    let timecreated: Int?
    let timemodified: Int?
}

// MARK: - Archivos privados (core_user_get_private_files_info / core_files_get_files)

struct MoodlePrivateFilesInfo: Decodable {
    let filecount: Int?
    let foldercount: Int?
    let filesize: Int?
    let filesizewithoutreferences: Int?
}

struct MoodleFilesResponse: Decodable {
    let parents: [MoodleFileNode]?
    let files: [MoodleFileNode]?
}

struct MoodleFileNode: Decodable, Identifiable, Hashable {
    var id: String { "\(contextid ?? 0)-\(filename ?? "")-\(filepath ?? "")-\(itemid ?? 0)" }
    let contextid: Int?
    let component: String?
    let filearea: String?
    let itemid: Int?
    let filepath: String?
    let filename: String?
    let filesize: Int?
    let fileurl: String?
    let timemodified: Int?
}

// MARK: - Grupos (core_group_*)

struct MoodleCourseUserGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let userid: Int?
    let groups: [MoodleGroup]
}

struct MoodleCourseUserGroupsResponse: Decodable {
    // Moodle devuelve directamente un arreglo, pero por si el sitio lo envuelve.
    let usergroups: [MoodleCourseUserGroup]?
}

struct MoodleActivityAllowedGroupsResponse: Decodable {
    let groups: [MoodleGroup]
    let canaccessallgroups: Bool?
}

// MARK: - Módulos sin visor (mod_data / mod_wiki / mod_book / mod_scorm)

struct MoodleDatabasesByCoursesResponse: Decodable {
    let databases: [MoodleDatabaseActivity]
}

struct MoodleDatabaseActivity: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let coursemodule: Int?
    let name: String?
    let intro: String?
}

struct MoodleWikisByCoursesResponse: Decodable {
    let wikis: [MoodleWiki]
}

struct MoodleWiki: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let coursemodule: Int?
    let name: String?
    let intro: String?
}

struct MoodleBooksByCoursesResponse: Decodable {
    let books: [MoodleBook]
}

struct MoodleBook: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let coursemodule: Int?
    let name: String?
    let intro: String?
}

struct MoodleScormsByCoursesResponse: Decodable {
    let scorms: [MoodleScorm]
}

struct MoodleScorm: Decodable, Identifiable, Hashable {
    let id: Int
    let course: Int?
    let coursemodule: Int?
    let name: String?
    let intro: String?
    let launch: Int?
}
