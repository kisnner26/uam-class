import Foundation

// MARK: - Auditoría de la API
//
// Qué funciones expone el token de UAM Virtual y cuáles de esas la app todavía
// no aprovecha.
//
// La lista de funciones NO se adivina: `core_webservice_get_site_info` devuelve
// exactamente lo que este token puede llamar, y ya la guardamos en
// `siteInfo.functions`. Hasta ahora solo se usaba para detectar el plugin de
// asistencia; acá se usa para lo que sirve de verdad.

@MainActor
enum APIAudit {

    /// Lo que la app ya llama. Se mantiene a mano contra el código fuente.
    static let used: Set<String> = [
        "core_badges_get_user_badges",
        "core_block_get_course_blocks", "core_block_get_dashboard_blocks",
        "core_calendar_create_calendar_events", "core_calendar_delete_calendar_events",
        "core_calendar_get_action_events_by_timesort",
        "core_calendar_get_calendar_monthly_view",
        "core_completion_get_activities_completion_status",
        "core_completion_update_activity_completion_status_manually",
        "core_course_get_contents", "core_course_view_course",
        "core_enrol_get_enrolled_users", "core_enrol_get_users_courses",
        "core_files_get_files",
        "core_group_get_activity_allowed_groups", "core_group_get_course_user_groups",
        "core_message_get_conversation_messages", "core_message_get_conversations",
        "core_message_get_unread_conversations_count",
        "core_message_search_users", "core_message_send_instant_messages",
        "core_message_send_messages_to_conversation",
        "core_notes_get_course_notes",
        "core_search_get_results",
        "core_user_get_course_user_profiles", "core_user_get_private_files_info",
        "core_user_get_users",
        "core_user_get_users_by_field", "core_webservice_get_site_info",
        "gradereport_overview_get_course_grades",
        "gradereport_user_get_grade_items",
        "message_popup_get_popup_notifications",
        "mod_assign_get_assignments", "mod_assign_get_submission_status",
        "mod_assign_save_submission", "mod_assign_submit_for_grading",
        "mod_book_get_books_by_courses",
        "mod_choice_delete_choice_responses", "mod_choice_get_choice_options",
        "mod_choice_get_choices_by_courses", "mod_choice_submit_choice_response",
        "mod_choicegroup_delete_choicegroup_responses",
        "mod_choicegroup_get_choicegroup_options",
        "mod_choicegroup_get_choicegroups_by_courses",
        "mod_choicegroup_submit_choicegroup_response",
        "mod_data_get_databases_by_courses",
        "mod_feedback_get_feedbacks_by_courses", "mod_feedback_get_page_items",
        "mod_feedback_process_page",
        "mod_forum_add_discussion", "mod_forum_add_discussion_post",
        "mod_forum_get_discussion_posts",
        "mod_forum_get_forum_discussions_paginated", "mod_forum_get_forums_by_courses",
        "mod_forum_set_subscription_state", "mod_forum_toggle_favourite_state",
        "mod_forum_view_forum",
        "mod_glossary_get_entries_by_letter", "mod_glossary_get_glossaries_by_courses",
        "mod_lesson_get_lessons_by_courses", "mod_lesson_get_page_data",
        "mod_lesson_launch_attempt",
        "mod_page_view_page",
        "mod_quiz_get_attempt_access_information", "mod_quiz_get_attempt_data",
        "mod_quiz_get_attempt_review", "mod_quiz_get_attempt_summary",
        "mod_quiz_get_quiz_access_information", "mod_quiz_get_quizzes_by_courses",
        "mod_quiz_get_user_attempts", "mod_quiz_process_attempt",
        "mod_quiz_save_attempt", "mod_quiz_start_attempt",
        "mod_quiz_view_attempt", "mod_quiz_view_quiz",
        "mod_resource_view_resource",
        "mod_scorm_get_scorms_by_courses",
        "mod_url_view_url",
        "mod_wiki_get_wikis_by_courses",
        "mod_workshop_get_submission_assessments", "mod_workshop_get_workshops_by_courses",
        "tool_mobile_get_autologin_key"
    ]

    // MARK: Oportunidades
    //
    // Funciones que, si el sitio las expone, habilitan algo concreto. El texto
    // dice QUÉ se podría construir, no qué hace la función: una lista de
    // nombres de API no le sirve a nadie para decidir.

    struct Opportunity {
        let functions: [String]
        let title: String
        let detail: String
        /// Cuánto cambiaría la app. Ordena la lista.
        let impact: Int   // 3 alto, 2 medio, 1 bajo
    }

    static let opportunities: [Opportunity] = [
        .init(functions: ["core_calendar_get_action_events_by_timesort",
                          "core_calendar_get_calendar_monthly_view"],
              title: "Agenda unificada",
              detail: "Hoy «Próximas entregas» solo lee tareas, así que un cuestionario que cierra mañana es invisible. Esta función devuelve TODOS los vencimientos de todos los módulos en una llamada, ya ordenados.",
              impact: 3),

        .init(functions: ["core_calendar_create_calendar_events",
                          "core_calendar_delete_calendar_events"],
              title: "Eventos propios en Moodle",
              detail: "El horario que cargaste a mano podría subir a tu calendario de Moodle y aparecer también en el móvil oficial.",
              impact: 1),

        .init(functions: ["message_popup_get_popup_notifications",
                          "core_message_get_unread_conversations_count"],
              title: "Notificaciones reales de Moodle",
              detail: "El feed propio del sitio: te calificaron, te respondieron, se abrió una tarea. Hoy la app calcula sus propios recordatorios; esto es lo que Moodle realmente emitió.",
              impact: 3),

        .init(functions: ["core_completion_get_activities_completion_status",
                          "core_completion_update_activity_completion_status_manually"],
              title: "Progreso real por actividad",
              detail: "Anillo de progreso verdadero en cada mosaico de materia, y poder tildar actividades desde la app.",
              impact: 2),

        .init(functions: ["core_course_view_course", "mod_resource_view_resource",
                          "mod_page_view_page", "mod_url_view_url",
                          "mod_forum_view_forum"],
              title: "Marcar como visto",
              detail: "La app LEE sin marcar. Si una materia usa «completar al ver» como criterio, leer el material desde acá no te cuenta y en el sitio figurás como que nunca lo abriste. Puede afectar una nota real.",
              impact: 3),

        .init(functions: ["core_search_get_results"],
              title: "Búsqueda global del sitio",
              detail: "Buscar dentro de TODO el contenido de Moodle desde la paleta de comandos, no solo en lo que la app ya descargó.",
              impact: 2),

        .init(functions: ["mod_lesson_get_lessons_by_courses",
                          "mod_lesson_launch_attempt", "mod_lesson_get_page_data"],
              title: "Lecciones",
              detail: "El módulo «Lección» se abre como genérico. Con esto se podría recorrer dentro de la app.",
              impact: 1),

        .init(functions: ["mod_workshop_get_workshops_by_courses",
                          "mod_workshop_get_submission_assessments"],
              title: "Talleres y evaluación entre pares",
              detail: "Ver qué te evaluaron los compañeros y qué te toca evaluar.",
              impact: 1),

        .init(functions: ["mod_glossary_get_glossaries_by_courses",
                          "mod_glossary_get_entries_by_letter"],
              title: "Glosarios",
              detail: "Los términos que el docente definió, buscables — y alimentarían el modo Estudiar.",
              impact: 1),

        .init(functions: ["core_notes_get_course_notes"],
              title: "Notas del docente sobre vos",
              detail: "Anotaciones que los docentes dejan en tu ficha y que casi nadie mira porque están escondidas.",
              impact: 2),

        .init(functions: ["core_user_get_private_files_info",
                          "core_files_get_files"],
              title: "Tus archivos privados",
              detail: "La mochila de archivos de Moodle, accesible desde la app.",
              impact: 1),

        .init(functions: ["mod_forum_set_subscription_state",
                          "mod_forum_toggle_favourite_state",
                          "mod_forum_add_discussion"],
              title: "Foros completos",
              detail: "Suscribirse, marcar favoritos y ABRIR discusiones nuevas. Hoy solo se puede responder a las existentes.",
              impact: 2),

        .init(functions: ["gradereport_overview_get_course_grades"],
              title: "Notas de todas las materias de una",
              detail: "Una sola llamada en vez de una por curso: Calificaciones cargaría mucho más rápido.",
              impact: 2),

        .init(functions: ["core_group_get_course_user_groups",
                          "core_group_get_activity_allowed_groups"],
              title: "Grupos del curso",
              detail: "Saber en qué grupo estás en cada materia sin deducirlo de la lista de participantes.",
              impact: 1),

        .init(functions: ["mod_attendance_get_courses_with_today_sessions",
                          "mod_attendance_get_session"],
              title: "Asistencia oficial",
              detail: "Si el sitio tiene el plugin, la asistencia REAL que lleva el docente, en vez de solo tu registro local.",
              impact: 3),

        .init(functions: ["mod_data_get_databases_by_courses",
                          "mod_wiki_get_wikis_by_courses",
                          "mod_book_get_books_by_courses",
                          "mod_scorm_get_scorms_by_courses"],
              title: "Módulos sin visor",
              detail: "Base de datos, wiki, libro y SCORM se abren como genéricos.",
              impact: 1)
    ]

    // MARK: Resultado

    struct Row: Identifiable {
        let id = UUID()
        let opportunity: Opportunity
        /// Cuáles de sus funciones expone realmente el sitio.
        let available: [String]
        let missing: [String]

        var isBuildable: Bool { !available.isEmpty }
        var isComplete: Bool { missing.isEmpty }
    }

    struct Report {
        var exposed: Int = 0
        var used: Int = 0
        var rows: [Row] = []
        /// Funciones expuestas que no usamos y que tampoco están en la lista de
        /// oportunidades. Es donde aparece lo que no anticipé.
        var uncatalogued: [String] = []

        var unusedCount: Int { max(0, exposed - used) }
        var coverage: Double { exposed == 0 ? 0 : Double(used) / Double(exposed) }
    }

    static func run(siteInfo: MoodleSiteInfo?) -> Report {
        guard let names = siteInfo?.functions?.map(\.name), !names.isEmpty else {
            return Report()
        }
        let exposed = Set(names)

        var report = Report()
        report.exposed = exposed.count
        report.used = exposed.intersection(used).count

        var catalogued = Set<String>()
        for opp in opportunities {
            let available = opp.functions.filter { exposed.contains($0) }
            let missing = opp.functions.filter { !exposed.contains($0) }
            catalogued.formUnion(opp.functions)
            report.rows.append(Row(opportunity: opp, available: available, missing: missing))
        }

        // Alto impacto primero, y dentro de eso lo que ya se puede construir.
        report.rows.sort { a, b in
            if a.isBuildable != b.isBuildable { return a.isBuildable }
            return a.opportunity.impact > b.opportunity.impact
        }

        report.uncatalogued = exposed
            .subtracting(used)
            .subtracting(catalogued)
            .sorted()

        return report
    }
}
