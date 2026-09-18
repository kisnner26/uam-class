import Foundation
import AppKit

/// Genera un archivo .ics con las entregas futuras y lo abre con Calendar.app.
enum ICalExporter {

    static func generate(assignments: [MoodleAssignment],
                         coursesById: [Int: MoodleCourse]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        df.timeZone = TimeZone(identifier: "UTC")

        var out = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//UAM Class//Kisnner//ES
        CALSCALE:GREGORIAN
        METHOD:PUBLISH

        """

        for a in assignments {
            guard let due = a.dueDateOrNil else { continue }
            let course = coursesById[a.course]
            let code = course.map { CourseInfo(course: $0).code } ?? "UAM"
            let summary = "\(code): \(HTMLClean.plain(a.name).replacingOccurrences(of: "\n", with: " "))"
            let uid = "uamclass-\(a.id)@uam.local"
            let dt = df.string(from: due)
            let dtEnd = df.string(from: due.addingTimeInterval(3600))
            let intro = HTMLClean.plain(a.intro).replacingOccurrences(of: "\n", with: "\\n")

            out.append("""
            BEGIN:VEVENT
            UID:\(uid)
            DTSTAMP:\(df.string(from: Date()))
            DTSTART:\(dt)
            DTEND:\(dtEnd)
            SUMMARY:\(summary)
            DESCRIPTION:\(intro)
            BEGIN:VALARM
            TRIGGER:-PT1H
            ACTION:DISPLAY
            DESCRIPTION:\(summary)
            END:VALARM
            END:VEVENT

            """)
        }
        out.append("END:VCALENDAR\n")
        return out
    }

    /// Escribe el .ics en tmp y lo abre en Calendar.
    static func exportAndOpen(assignments: [MoodleAssignment],
                              coursesById: [Int: MoodleCourse]) {
        let ics = generate(assignments: assignments, coursesById: coursesById)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("UAM-Class-\(Int(Date().timeIntervalSince1970)).ics")
        do {
            try ics.data(using: .utf8)?.write(to: tmp)
            NSWorkspace.shared.open(tmp)
        } catch {
            // silencioso
        }
    }
}
