import Foundation
import UserNotifications

/// Programa recordatorios locales para entregas Moodle.
/// Cancela y re-schedule cada vez que se refresca; nunca duplica.
enum NotificationScheduler {

    private static let idPrefix = "UAMClass.due."

    /// Reemplaza todos los recordatorios de entregas por los que están vigentes.
    static func schedule(assignments: [MoodleAssignment],
                         coursesById: [Int: MoodleCourse]) async {
        // Solo si hay bundle identifier (evita crash en swift run sin .app)
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()

        // Limpiamos los previos de la app
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ourIds)

        let now = Date()
        for a in assignments {
            guard let due = a.dueDateOrNil, due > now else { continue }
            let course = coursesById[a.course]
            let courseCode = course.map { CourseInfo(course: $0).code } ?? ""

            // 24h antes
            let day = due.addingTimeInterval(-24 * 3600)
            if day > now {
                try? await schedule(id: "\(a.id).24h",
                                    title: "\(courseCode) · Entrega mañana",
                                    body: "\(HTMLClean.plain(a.name)) vence \(shortDate(due))",
                                    date: day)
            }

            // 1h antes
            let hour = due.addingTimeInterval(-1 * 3600)
            if hour > now {
                try? await schedule(id: "\(a.id).1h",
                                    title: "\(courseCode) · En 1 hora",
                                    body: HTMLClean.plain(a.name),
                                    date: hour)
            }
        }
    }

    private static func schedule(id: String, title: String, body: String, date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: idPrefix + id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(req)
    }

    private static func shortDate(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }
}
