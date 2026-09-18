import Foundation

// MARK: - Endpoints nuevos detectados por `APIAudit`
//
// Un método por función confirmada disponible en el token de UAM Virtual
// (ver `APIAudit.opportunities`). Se deja afuera `mod_attendance_*`: el sitio
// no expone ese plugin.

extension MoodleClient {

    // MARK: Agenda unificada

    /// Todos los vencimientos (tareas, cuestionarios, foros con fecha, etc.),
    /// ya ordenados por Moodle. `timesortfrom` en `nil` = desde ahora.
    func actionEventsByTimesort(from timesortfrom: Int? = nil,
                                to timesortto: Int? = nil,
                                limitNum: Int = 50) async throws -> [MoodleTimesortEvent] {
        var params: [String: String] = [
            "limitnum": String(limitNum),
            "limittononsuspendedevents": "1"
        ]
        if let timesortfrom { params["timesortfrom"] = String(timesortfrom) }
        if let timesortto { params["timesortto"] = String(timesortto) }
        let resp: MoodleTimesortEventsResponse = try await rest(
            "core_calendar_get_action_events_by_timesort",
            params: params, as: MoodleTimesortEventsResponse.self)
        return resp.events ?? []
    }

    /// Vista mensual del calendario (incluye eventos de todos los cursos si
    /// `courseId` es `0`).
    func calendarMonthlyView(year: Int, month: Int, courseId: Int = 0) async throws -> MoodleMonthlyViewResponse {
        try await rest("core_calendar_get_calendar_monthly_view",
                       params: [
                           "year": String(year),
                           "month": String(month),
                           "courseid": String(courseId),
                           "categoryid": "0",
                           "includenavigation": "1",
                           "mini": "0"
                       ],
                       as: MoodleMonthlyViewResponse.self)
    }

    /// Crea un evento propio de usuario en el calendario de Moodle.
    func createCalendarEvent(name: String, description: String = "",
                             timestart: Int, timeduration: Int = 0) async throws -> MoodleTimesortEvent? {
        let resp: MoodleCreatedEventsResponse = try await rest(
            "core_calendar_create_calendar_events",
            params: [
                "events[0][name]": name,
                "events[0][description]": description,
                "events[0][format]": "1",
                "events[0][eventtype]": "user",
                "events[0][timestart]": String(timestart),
                "events[0][timeduration]": String(timeduration),
                "events[0][courseid]": "0",
                "events[0][repeats]": "0"
            ],
            as: MoodleCreatedEventsResponse.self)
        if let w = resp.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
        return resp.events?.first
    }

    func deleteCalendarEvent(eventId: Int, repeatSeries: Bool = false) async throws {
        struct Ack: Decodable { let warnings: [MoodleWarning]? }
        let ack: Ack = try await rest("core_calendar_delete_calendar_events",
                                      params: [
                                          "events[0][eventid]": String(eventId),
                                          "events[0][repeat]": repeatSeries ? "1" : "0"
                                      ],
                                      as: Ack.self)
        if let w = ack.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
    }

    // MARK: Notificaciones reales

    func popupNotifications(userId: Int, limit: Int = 30, offset: Int = 0) async throws -> MoodlePopupNotificationsResponse {
        try await rest("message_popup_get_popup_notifications",
                       params: [
                           "useridto": String(userId),
                           "newestfirst": "1",
                           "limit": String(limit),
                           "offset": String(offset)
                       ],
                       as: MoodlePopupNotificationsResponse.self)
    }

    func unreadConversationsCount(userId: Int) async throws -> Int {
        let resp = try await rest("core_message_get_unread_conversations_count",
                                  params: ["useridto": String(userId)],
                                  as: MoodleUnreadConversationsCount.self)
        return resp.count
    }

    // MARK: Marcar como visto
    //
    // Cada `mod_*_view_*` le dice a Moodle "el usuario abrió esto" — necesario
    // para que el criterio de finalización "completar al ver" cuente. Todas
    // devuelven `{status, warnings}`; solo nos importa si hubo warning.

    private struct ViewAck: Decodable { let status: Bool?; let warnings: [MoodleWarning]? }

    private func sendView(_ function: String, idField: String, id: Int) async throws {
        let ack: ViewAck = try await rest(function, params: [idField: String(id)], as: ViewAck.self)
        if let w = ack.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
    }

    func markCourseViewed(courseId: Int) async throws {
        try await sendView("core_course_view_course", idField: "courseid", id: courseId)
    }

    func markResourceViewed(resourceId: Int) async throws {
        try await sendView("mod_resource_view_resource", idField: "resourceid", id: resourceId)
    }

    func markPageViewed(pageId: Int) async throws {
        try await sendView("mod_page_view_page", idField: "pageid", id: pageId)
    }

    func markUrlViewed(urlId: Int) async throws {
        try await sendView("mod_url_view_url", idField: "urlid", id: urlId)
    }

    func markForumViewed(forumId: Int) async throws {
        try await sendView("mod_forum_view_forum", idField: "forumid", id: forumId)
    }

    // MARK: Progreso real por actividad

    func activitiesCompletionStatus(courseId: Int, userId: Int) async throws -> [MoodleActivityCompletionStatus] {
        let resp: MoodleActivitiesCompletionResponse = try await rest(
            "core_completion_get_activities_completion_status",
            params: ["courseid": String(courseId), "userid": String(userId)],
            as: MoodleActivitiesCompletionResponse.self)
        return resp.statuses
    }

    /// Tilda (o destilda) manualmente una actividad. Solo funciona si su
    /// criterio de finalización es "marcado manual".
    func setActivityCompletion(cmid: Int, completed: Bool) async throws {
        struct Ack: Decodable { let status: Bool?; let warnings: [MoodleWarning]? }
        let ack: Ack = try await rest(
            "core_completion_update_activity_completion_status_manually",
            params: ["cmid": String(cmid), "completed": completed ? "1" : "0"],
            as: Ack.self)
        if let w = ack.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
    }

    // MARK: Búsqueda global

    func searchSite(query: String, page: Int = 0) async throws -> MoodleSearchResultsResponse {
        try await rest("core_search_get_results",
                       params: [
                           "search[query]": query,
                           "search[order]": "relevance",
                           "page": String(page)
                       ],
                       as: MoodleSearchResultsResponse.self)
    }

    // MARK: Notas del docente

    /// `courseId: 0` trae notas de todos los cursos.
    func courseNotes(userId: Int, courseId: Int = 0) async throws -> MoodleCourseNotesByType? {
        let resp: MoodleCourseNotesResponse = try await rest(
            "core_notes_get_course_notes",
            params: ["courseid": String(courseId), "userid": String(userId)],
            as: MoodleCourseNotesResponse.self)
        return resp.notes
    }

    // MARK: Foros completos

    func setForumSubscription(forumId: Int, discussionId: Int = 0, subscribe: Bool) async throws {
        struct Ack: Decodable { let status: Bool? }
        var params = ["forumid": String(forumId), "targetstate": subscribe ? "1" : "0"]
        if discussionId != 0 { params["discussionid"] = String(discussionId) }
        _ = try await rest("mod_forum_set_subscription_state", params: params, as: Ack.self)
    }

    func toggleForumFavourite(forumId: Int, discussionId: Int, favourite: Bool) async throws {
        struct Ack: Decodable { let status: Bool? }
        _ = try await rest("mod_forum_toggle_favourite_state",
                           params: [
                               "forumid": String(forumId),
                               "discussionid": String(discussionId),
                               "targetstate": favourite ? "1" : "0"
                           ],
                           as: Ack.self)
    }

    /// Abre una discusión nueva en un foro. `groupId: -1` = todos los grupos.
    func addForumDiscussion(forumId: Int, subject: String, message: String,
                            groupId: Int = -1) async throws -> Int {
        struct Reply: Decodable { let discussionid: Int?; let warnings: [MoodleWarning]? }
        let r: Reply = try await rest("mod_forum_add_discussion",
                                      params: [
                                          "forumid": String(forumId),
                                          "subject": subject,
                                          "message": message,
                                          "messageformat": "1",
                                          "groupid": String(groupId)
                                      ],
                                      as: Reply.self)
        if let w = r.warnings?.first, let msg = w.message {
            throw APIError(message: msg, errorcode: w.warningcode)
        }
        return r.discussionid ?? 0
    }

    // MARK: Notas de todas las materias de una

    func overviewGrades(userId: Int) async throws -> [MoodleOverviewGrade] {
        let resp: MoodleOverviewGradesResponse = try await rest(
            "gradereport_overview_get_course_grades",
            params: ["userid": String(userId)],
            as: MoodleOverviewGradesResponse.self)
        return resp.grades
    }

    // MARK: Lecciones

    func lessons(courseIds: [Int]) async throws -> [MoodleLesson] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleLessonsByCoursesResponse = try await rest(
            "mod_lesson_get_lessons_by_courses", params: params,
            as: MoodleLessonsByCoursesResponse.self)
        return resp.lessons
    }

    func launchLessonAttempt(lessonId: Int, pageId: Int = 0) async throws -> MoodleLessonAttemptResponse {
        try await rest("mod_lesson_launch_attempt",
                       params: ["lessonid": String(lessonId), "pageid": String(pageId)],
                       as: MoodleLessonAttemptResponse.self)
    }

    func lessonPageData(lessonId: Int, pageId: Int) async throws -> MoodleLessonPageDataResponse {
        try await rest("mod_lesson_get_page_data",
                       params: [
                           "lessonid": String(lessonId),
                           "pageid": String(pageId),
                           "returncontents": "1"
                       ],
                       as: MoodleLessonPageDataResponse.self)
    }

    // MARK: Talleres

    func workshops(courseIds: [Int]) async throws -> [MoodleWorkshop] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleWorkshopsByCoursesResponse = try await rest(
            "mod_workshop_get_workshops_by_courses", params: params,
            as: MoodleWorkshopsByCoursesResponse.self)
        return resp.workshops
    }

    func workshopSubmissionAssessments(submissionId: Int) async throws -> [MoodleWorkshopAssessment] {
        let resp: MoodleWorkshopSubmissionAssessmentsResponse = try await rest(
            "mod_workshop_get_submission_assessments",
            params: ["submissionid": String(submissionId)],
            as: MoodleWorkshopSubmissionAssessmentsResponse.self)
        return resp.assessments
    }

    // MARK: Glosarios

    func glossaries(courseIds: [Int]) async throws -> [MoodleGlossary] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleGlossariesByCoursesResponse = try await rest(
            "mod_glossary_get_glossaries_by_courses", params: params,
            as: MoodleGlossariesByCoursesResponse.self)
        return resp.glossaries
    }

    /// `letter: "ALL"` trae todos los términos.
    func glossaryEntries(glossaryId: Int, letter: String = "ALL") async throws -> [MoodleGlossaryEntry] {
        let resp: MoodleGlossaryEntriesResponse = try await rest(
            "mod_glossary_get_entries_by_letter",
            params: ["id": String(glossaryId), "letter": letter, "from": "0", "limit": "0"],
            as: MoodleGlossaryEntriesResponse.self)
        return resp.entries
    }

    // MARK: Archivos privados

    func privateFilesInfo(userId: Int) async throws -> MoodlePrivateFilesInfo {
        try await rest("core_user_get_private_files_info",
                       params: ["userid": String(userId)],
                       as: MoodlePrivateFilesInfo.self)
    }

    /// Explora el área "Archivos privados" del usuario. `filepath: "/"` es la raíz.
    func privateFiles(contextId: Int, filepath: String = "/") async throws -> MoodleFilesResponse {
        try await rest("core_files_get_files",
                       params: [
                           "contextid": String(contextId),
                           "component": "user",
                           "filearea": "private",
                           "itemid": "0",
                           "filepath": filepath,
                           "filename": ""
                       ],
                       as: MoodleFilesResponse.self)
    }

    // MARK: Grupos del curso

    func courseUserGroups(courseId: Int, userId: Int) async throws -> [MoodleGroup] {
        // Moodle devuelve un arreglo de `{id: userid, groups: [...]}` sin envolver.
        let rows: [MoodleCourseUserGroup] = try await rest(
            "core_group_get_course_user_groups",
            params: ["courseid": String(courseId), "userid": String(userId)],
            as: [MoodleCourseUserGroup].self)
        return rows.first(where: { $0.userid == userId })?.groups ?? rows.first?.groups ?? []
    }

    func activityAllowedGroups(cmid: Int, userId: Int) async throws -> [MoodleGroup] {
        let resp: MoodleActivityAllowedGroupsResponse = try await rest(
            "core_group_get_activity_allowed_groups",
            params: ["cmid": String(cmid), "userid": String(userId)],
            as: MoodleActivityAllowedGroupsResponse.self)
        return resp.groups
    }

    // MARK: Módulos sin visor

    func databases(courseIds: [Int]) async throws -> [MoodleDatabaseActivity] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleDatabasesByCoursesResponse = try await rest(
            "mod_data_get_databases_by_courses", params: params,
            as: MoodleDatabasesByCoursesResponse.self)
        return resp.databases
    }

    func wikis(courseIds: [Int]) async throws -> [MoodleWiki] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleWikisByCoursesResponse = try await rest(
            "mod_wiki_get_wikis_by_courses", params: params,
            as: MoodleWikisByCoursesResponse.self)
        return resp.wikis
    }

    func books(courseIds: [Int]) async throws -> [MoodleBook] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleBooksByCoursesResponse = try await rest(
            "mod_book_get_books_by_courses", params: params,
            as: MoodleBooksByCoursesResponse.self)
        return resp.books
    }

    func scorms(courseIds: [Int]) async throws -> [MoodleScorm] {
        var params: [String: String] = [:]
        for (i, id) in courseIds.enumerated() { params["courseids[\(i)]"] = String(id) }
        let resp: MoodleScormsByCoursesResponse = try await rest(
            "mod_scorm_get_scorms_by_courses", params: params,
            as: MoodleScormsByCoursesResponse.self)
        return resp.scorms
    }
}
