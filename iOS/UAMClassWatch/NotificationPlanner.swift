import Foundation
import UserNotifications

/// Avisos de clase en el reloj: 1 hora antes y 15 minutos antes de que
/// empiece cada bloque, todas las semanas. Se recalculan enteros cada vez
/// que llega un horario nuevo del iPhone — más simple y más seguro que
/// tratar de diffear cuáles cambiaron.
enum NotificationPlanner {
    private static let idPrefix = "uamclass.classreminder."

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func reschedule(for slots: [ClassSlot]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for slot in slots {
                schedule(slot, offsetMinutes: 60, label: "en 1 hora", center: center)
                schedule(slot, offsetMinutes: 15, label: "en 15 minutos", center: center)
            }
        }
    }

    private static func schedule(_ slot: ClassSlot, offsetMinutes: Int, label: String,
                                  center: UNUserNotificationCenter) {
        var comps = DateComponents()
        comps.weekday = slot.weekday.rawValue
        comps.hour = slot.startMinutes / 60
        comps.minute = slot.startMinutes % 60

        let calendar = Calendar.current
        // Próxima ocurrencia real de "ese día de la semana a esa hora", y de ahí
        // restamos minutos como fecha (no como aritmética de reloj) para que una
        // clase a las 00:20 corra el aviso al día anterior sin romperse.
        guard let nextOccurrence = calendar.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime),
              let triggerDate = calendar.date(byAdding: .minute, value: -offsetMinutes, to: nextOccurrence)
        else { return }

        let triggerComps = calendar.dateComponents([.weekday, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = slot.courseName
        content.body = body(for: slot, label: label)
        content.sound = .default

        let identifier = "\(idPrefix)\(slot.id.uuidString).\(offsetMinutes)"
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private static func body(for slot: ClassSlot, label: String) -> String {
        var parts = ["Empieza \(label)"]
        if !slot.section.isEmpty { parts.append(slot.section) }
        if let room = slot.roomText { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}
